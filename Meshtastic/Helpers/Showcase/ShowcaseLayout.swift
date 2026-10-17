//
//  ShowcaseLayout.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd

/// Where a node sits in the showcase: a cell in the wall rack, counted across pages.
enum ShowcaseSlot: Hashable, Sendable {
	case rack(Int)
}

/// The wall rack's cells: a grid sized so each cell is still a comfortable target from the chair,
/// shown one page at a time.
struct ShowcaseRackGrid: Equatable, Sendable {
	let columns: Int
	let rows: Int
	/// Center-to-center spacing, in meters.
	let pitch: Float

	var perPage: Int { columns * rows }

	/// A target should be about 6% of its distance across (a little over 3°); cells are spaced a
	/// little wider than that, inside a margin around the panel's edge.
	static func fitting(size: SIMD2<Float>, viewingDistance: Float, margin: Float = 0.06) -> ShowcaseRackGrid {
		let target = 0.06 * viewingDistance
		let pitch = target * 1.15
		let columns = max(1, Int(((size.x - 2 * margin) / pitch).rounded(.down)))
		let rows = max(1, Int(((size.y - 2 * margin) / pitch).rounded(.down)))
		return ShowcaseRackGrid(columns: columns, rows: rows, pitch: pitch)
	}

	/// The grid for the room's rack, seen from the seat.
	static func forRoom(rack: ShowcaseAnchorPose) -> ShowcaseRackGrid {
		fitting(size: ShowcaseRoomGeometry.rackSize, viewingDistance: simd_distance(ShowcaseRoomGeometry.seatedEye, rack.position))
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

/// Decides which node goes where: every node, the connected radio included, goes into the wall
/// rack, page by page, until it is full. The tables' models are the device showcase, not nodes.
///
/// Nodes keep their cell: a new node takes the first free one, and a node counts as online or
/// offline only after it has stayed that way for `hysteresis`, so the rack doesn't flicker.
struct ShowcaseLayout {
	static let onlineWindow: TimeInterval = 2 * 60 * 60
	static let hysteresis: TimeInterval = 2 * 60
	static let maxRackPages = 4

	let grid: ShowcaseRackGrid
	let maxRackPages: Int
	private(set) var slots: [Int64: ShowcaseSlot] = [:]
	/// Nodes there was no place for.
	private(set) var overflow = 0
	private var onlineStates: [Int64: OnlineState] = [:]

	private struct OnlineState {
		var isOnline: Bool
		/// When the snapshot started disagreeing with `isOnline`.
		var changingSince: Date?
	}

	init(grid: ShowcaseRackGrid, maxRackPages: Int = ShowcaseLayout.maxRackPages) {
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
	func node(in slot: ShowcaseSlot) -> Int64? {
		slots.first { $0.value == slot }?.key
	}

	/// Places `nodes`, which come in showcase order (see `ShowcaseNodeOrdering`).
	mutating func update(_ nodes: [ShowcaseNodeSnapshot], now: Date) {
		let present = Set(nodes.map(\.id))
		slots = slots.filter { present.contains($0.key) }
		onlineStates = onlineStates.filter { present.contains($0.key) }
		for node in nodes { updateOnline(node, now: now) }

		let taken = Set(slots.values)
		var rackFree = (0..<rackCapacity).filter { !taken.contains(.rack($0)) }[...]
		overflow = 0
		for node in nodes where slots[node.id] == nil {
			if let index = rackFree.popFirst() {
				slots[node.id] = .rack(index)
			} else {
				overflow += 1
			}
		}
		// The connected radio always has a place: on a full rack it takes the one held by the node
		// that comes last in showcase order, which joins the overflow in its stead.
		if let radio = nodes.first(where: \.isConnectedRadio), slots[radio.id] == nil {
			let rank = Dictionary(nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
			if let last = slots.keys.max(by: { (rank[$0] ?? .max) < (rank[$1] ?? .max) }), let place = slots[last] {
				slots[last] = nil
				slots[radio.id] = place
			}
		}
	}

	private mutating func updateOnline(_ node: ShowcaseNodeSnapshot, now: Date) {
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
enum ShowcasePlacement {
	/// The place's position and facing in the room. Rack cells are on the face of the panel.
	static func pose(of slot: ShowcaseSlot, grid: ShowcaseRackGrid, anchor: (ShowcaseAnchor) -> ShowcaseAnchorPose) -> ShowcaseAnchorPose {
		switch slot {
		case .rack(let index):
			let base = anchor(.wallRack)
			let center = grid.center(ofCellOnPage: index % grid.perPage)
			return ShowcaseAnchorPose(base.position + base.orientation.act(SIMD3(center.x, center.y, 0)), orientation: base.orientation)
		}
	}
}
