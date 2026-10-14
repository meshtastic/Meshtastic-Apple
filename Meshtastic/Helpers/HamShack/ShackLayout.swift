//
//  ShackLayout.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd

/// Where a node sits in the shack.
enum ShackSlot: Hashable, Sendable {
	/// The connected radio, in the middle of the desk.
	case deskRadio
	/// A cell in the wall rack, counted across pages.
	case rack(Int)

	var tier: ShackTier {
		switch self {
		case .deskRadio: .deskRadio
		case .rack: .rack
		}
	}
}

enum ShackTier: Int, Comparable, Sendable {
	case deskRadio, rack
	static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The wall rack's cells: a grid sized so each cell is still a comfortable target from the chair,
/// shown one page at a time.
struct ShackRackGrid: Equatable, Sendable {
	let columns: Int
	let rows: Int
	/// Center-to-center spacing, in meters.
	let pitch: Float

	var perPage: Int { columns * rows }

	/// A target should be about 6% of its distance across (a little over 3°); cells are spaced a
	/// little wider than that, inside a margin around the panel's edge.
	static func fitting(size: SIMD2<Float>, viewingDistance: Float, margin: Float = 0.06) -> ShackRackGrid {
		let target = 0.06 * viewingDistance
		let pitch = target * 1.15
		let columns = max(1, Int(((size.x - 2 * margin) / pitch).rounded(.down)))
		let rows = max(1, Int(((size.y - 2 * margin) / pitch).rounded(.down)))
		return ShackRackGrid(columns: columns, rows: rows, pitch: pitch)
	}

	/// The grid for the room's rack, seen from the seat.
	static func forRoom(rack: ShackAnchorPose) -> ShackRackGrid {
		fitting(size: ShackRoomGeometry.rackSize, viewingDistance: simd_distance(ShackRoomGeometry.seatedEye, rack.position))
	}

	/// The center of a cell on its page, in the rack's own plane: +X to the viewer's right, +Y up,
	/// the panel's middle at the origin. Row 0 is the top.
	func center(ofCellOnPage index: Int) -> SIMD2<Float> {
		let column = index % columns, row = index / columns
		return SIMD2(
			-Float(columns) * pitch / 2 + pitch * (Float(column) + 0.5),
			Float(rows) * pitch / 2 - pitch * (Float(row) + 0.5)
		)
	}

	/// The cell on the page under a point in the rack's plane, nil off the grid.
	func cell(at point: SIMD2<Float>) -> Int? {
		let column = Int(((point.x + Float(columns) * pitch / 2) / pitch).rounded(.down))
		let row = Int(((Float(rows) * pitch / 2 - point.y) / pitch).rounded(.down))
		guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
		return row * columns + column
	}
}

/// Decides which node goes where. The connected radio takes the desk; everyone else goes into the
/// wall rack, page by page, until it is full. The shelves hold the device showroom, not nodes.
///
/// Nodes keep their cell: a new node takes the first free one, and a node counts as online or
/// offline only after it has stayed that way for `hysteresis`, so the rack doesn't flicker.
struct ShackLayout {
	static let onlineWindow: TimeInterval = 2 * 60 * 60
	static let hysteresis: TimeInterval = 2 * 60
	static let maxRackPages = 4

	let grid: ShackRackGrid
	let maxRackPages: Int
	private(set) var slots: [Int64: ShackSlot] = [:]
	/// Nodes there was no place for.
	private(set) var overflow = 0
	private var onlineStates: [Int64: OnlineState] = [:]

	private struct OnlineState {
		var isOnline: Bool
		/// When the snapshot started disagreeing with `isOnline`.
		var changingSince: Date?
	}

	init(grid: ShackRackGrid, maxRackPages: Int = ShackLayout.maxRackPages) {
		self.grid = grid
		self.maxRackPages = maxRackPages
	}

	var rackCapacity: Int { grid.perPage * maxRackPages }

	/// Pages in use: up to the page of the last occupied cell, at least one.
	var rackPageCount: Int {
		let last = slots.values.compactMap { if case .rack(let index) = $0 { index } else { nil } }.max()
		return last.map { $0 / grid.perPage + 1 } ?? 1
	}

	/// Online as the room shows it, after hysteresis.
	func isOnline(_ nodeNum: Int64) -> Bool {
		onlineStates[nodeNum]?.isOnline ?? false
	}

	/// The nodes on one rack page, keyed by their cell on that page.
	func rackPage(_ page: Int) -> [Int: Int64] {
		var result: [Int: Int64] = [:]
		for (num, slot) in slots {
			if case .rack(let index) = slot, index / grid.perPage == page {
				result[index % grid.perPage] = num
			}
		}
		return result
	}

	/// The node in a place, if any.
	func node(in slot: ShackSlot) -> Int64? {
		slots.first { $0.value == slot }?.key
	}

	/// Places `nodes`, which come in shack order (see `ShackNodeOrdering`).
	mutating func update(_ nodes: [ShackNodeSnapshot], now: Date) {
		let present = Set(nodes.map(\.id))
		slots = slots.filter { present.contains($0.key) }
		onlineStates = onlineStates.filter { present.contains($0.key) }
		for node in nodes { updateOnline(node, now: now) }

		// The desk follows the connection at once, both ways.
		for node in nodes where (slots[node.id] == .deskRadio) != node.isConnectedRadio {
			slots[node.id] = nil
		}

		let taken = Set(slots.values)
		var deskFree = !taken.contains(.deskRadio)
		var rackFree = (0..<rackCapacity).filter { !taken.contains(.rack($0)) }[...]
		overflow = 0
		for node in nodes where slots[node.id] == nil {
			if node.isConnectedRadio, deskFree {
				deskFree = false
				slots[node.id] = .deskRadio
			} else if let index = rackFree.popFirst() {
				slots[node.id] = .rack(index)
			} else {
				overflow += 1
			}
		}
	}

	private mutating func updateOnline(_ node: ShackNodeSnapshot, now: Date) {
		guard var state = onlineStates[node.id] else {
			onlineStates[node.id] = OnlineState(isOnline: node.isOnline)
			return
		}
		if node.isOnline == state.isOnline {
			state.changingSince = nil
		} else if let since = state.changingSince {
			if now.timeIntervalSince(since) >= Self.hysteresis {
				state.isOnline = node.isOnline
				state.changingSince = nil
			}
		} else {
			state.changingSince = now
		}
		onlineStates[node.id] = state
	}
}

/// Where each place is in the room, from the room's anchors.
enum ShackPlacement {
	/// The place's position and facing in the room. Rack cells are on the face of the panel.
	static func pose(of slot: ShackSlot, grid: ShackRackGrid, anchor: (ShackAnchor) -> ShackAnchorPose) -> ShackAnchorPose {
		switch slot {
		case .deskRadio:
			return anchor(.deskRadio)
		case .rack(let index):
			let base = anchor(.wallRack)
			let center = grid.center(ofCellOnPage: index % grid.perPage)
			return ShackAnchorPose(base.position + base.orientation.act(SIMD3(center.x, center.y, 0)), orientation: base.orientation)
		}
	}
}
