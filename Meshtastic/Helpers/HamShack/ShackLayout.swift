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
	/// One of the favorites beside it.
	case desk(Int)
	/// A place on a hutch shelf: shelf 0 is the lowest.
	case shelf(Int, Int)
	/// A cell in the wall rack, counted across pages.
	case rack(Int)

	var tier: ShackTier {
		switch self {
		case .deskRadio: .deskRadio
		case .desk: .desk
		case .shelf: .shelf
		case .rack: .rack
		}
	}
}

enum ShackTier: Int, Comparable, Sendable {
	case deskRadio, desk, shelf, rack
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

/// Decides which node goes where. The connected radio takes the middle of the desk and up to four
/// favorites sit beside it; the shelves hold the remaining favorites and then online nodes; the
/// rest go into the wall rack, page by page, until it is full.
///
/// Nodes keep their place: a new node takes the first free place in its tier straight away, but
/// nodes only move between tiers every `promotionInterval`, and a node counts as online or offline
/// only after it has stayed that way for `hysteresis`, so the room doesn't shuffle.
struct ShackLayout {
	static let onlineWindow: TimeInterval = 2 * 60 * 60
	static let deskSlots = 4
	static let shelfCount = 3
	static let perShelf = 8
	static let shelfCapacity = shelfCount * perShelf
	static let promotionInterval: TimeInterval = 30
	static let hysteresis: TimeInterval = 2 * 60
	static let maxRackPages = 4

	let grid: ShackRackGrid
	let maxRackPages: Int
	private(set) var slots: [Int64: ShackSlot] = [:]
	/// Nodes there was no place for.
	private(set) var overflow = 0
	private var onlineStates: [Int64: OnlineState] = [:]
	private var lastPromotion: Date?

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

		let promote = lastPromotion.map { now.timeIntervalSince($0) >= Self.promotionInterval } ?? true
		if promote { lastPromotion = now }
		let desired = desiredTiers(nodes)

		for (num, slot) in slots {
			let tier = desired[num] ?? .rack
			// The desk radio follows the connection at once; other moves wait for a promotion.
			if (slot.tier == .deskRadio) != (tier == .deskRadio) || (promote && slot.tier != tier) {
				slots[num] = nil
			}
		}

		var free = FreePlaces(layout: self)
		overflow = 0
		for node in nodes where slots[node.id] == nil {
			if let slot = free.take(from: desired[node.id] ?? .rack) {
				slots[node.id] = slot
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

	/// The tier each node should be in. Nodes already on the desk or a shelf keep it while they
	/// still qualify, so a full desk or shelf doesn't swap nodes each time last-heard order shifts.
	private func desiredTiers(_ nodes: [ShackNodeSnapshot]) -> [Int64: ShackTier] {
		var result: [Int64: ShackTier] = [:]
		var favorites: [ShackNodeSnapshot] = []
		var online: [ShackNodeSnapshot] = []
		for node in nodes {
			if node.isConnectedRadio {
				result[node.id] = .deskRadio
			} else if node.isFavorite {
				favorites.append(node)
			} else if isOnline(node.id) {
				online.append(node)
			} else {
				result[node.id] = .rack
			}
		}
		let desk = stickyFirst(favorites, in: .desk)
		for node in desk.prefix(Self.deskSlots) { result[node.id] = .desk }
		let shelf = stickyFirst(Array(desk.dropFirst(Self.deskSlots)), in: .shelf) + stickyFirst(online, in: .shelf)
		for (index, node) in shelf.enumerated() {
			result[node.id] = index < Self.shelfCapacity ? .shelf : .rack
		}
		return result
	}

	/// `nodes` with those already in `tier` first, each group keeping its order.
	private func stickyFirst(_ nodes: [ShackNodeSnapshot], in tier: ShackTier) -> [ShackNodeSnapshot] {
		let holding = nodes.filter { slots[$0.id]?.tier == tier }
		return holding + nodes.filter { slots[$0.id]?.tier != tier }
	}

	/// The free places in each tier, lowest first. A node whose tier is full drops to the next.
	private struct FreePlaces {
		var deskRadio: Bool
		var desk: [Int]
		var shelf: [(Int, Int)]
		var rack: [Int]

		init(layout: ShackLayout) {
			let taken = Set(layout.slots.values)
			deskRadio = !taken.contains(.deskRadio)
			desk = (0..<ShackLayout.deskSlots).filter { !taken.contains(.desk($0)) }
			shelf = (0..<ShackLayout.shelfCount).flatMap { shelf in
				(0..<ShackLayout.perShelf).map { (shelf, $0) }
			}.filter { !taken.contains(.shelf($0.0, $0.1)) }
			rack = (0..<layout.rackCapacity).filter { !taken.contains(.rack($0)) }
		}

		mutating func take(from tier: ShackTier) -> ShackSlot? {
			switch tier {
			case .deskRadio:
				if deskRadio {
					deskRadio = false
					return .deskRadio
				}
				return take(from: .desk)
			case .desk:
				if !desk.isEmpty { return .desk(desk.removeFirst()) }
				return take(from: .shelf)
			case .shelf:
				if !shelf.isEmpty {
					let place = shelf.removeFirst()
					return .shelf(place.0, place.1)
				}
				return take(from: .rack)
			case .rack:
				return rack.isEmpty ? nil : .rack(rack.removeFirst())
			}
		}
	}
}

/// Where each place is in the room, from the room's anchors.
enum ShackPlacement {
	/// Shelf places are spread evenly along the shelf.
	static var shelfPitch: Float { ShackRoomGeometry.shelfLength / Float(ShackLayout.perShelf) }

	/// The favorites stand in a two-by-two block to the right of the desk radio.
	static let deskOffsets: [SIMD3<Float>] = [
		SIMD3(0.25, 0, -0.08), SIMD3(0.43, 0, -0.08),
		SIMD3(0.25, 0, 0.13), SIMD3(0.43, 0, 0.13)
	]

	/// The place's position and facing in the room. Rack cells are on the face of the panel.
	static func pose(of slot: ShackSlot, grid: ShackRackGrid, anchor: (ShackAnchor) -> ShackAnchorPose) -> ShackAnchorPose {
		switch slot {
		case .deskRadio:
			return anchor(.deskRadio)
		case .desk(let index):
			let base = anchor(.deskRadio)
			return ShackAnchorPose(base.position + base.orientation.act(deskOffsets[index % deskOffsets.count]), orientation: base.orientation)
		case .shelf(let shelf, let index):
			let base = anchor(ShackAnchor.shelves[min(max(shelf, 0), ShackAnchor.shelves.count - 1)])
			let x = -ShackRoomGeometry.shelfLength / 2 + shelfPitch * (Float(index) + 0.5)
			return ShackAnchorPose(base.position + base.orientation.act(SIMD3(x, 0, 0)), orientation: base.orientation)
		case .rack(let index):
			let base = anchor(.wallRack)
			let center = grid.center(ofCellOnPage: index % grid.perPage)
			return ShackAnchorPose(base.position + base.orientation.act(SIMD3(center.x, center.y, 0)), orientation: base.orientation)
		}
	}
}
