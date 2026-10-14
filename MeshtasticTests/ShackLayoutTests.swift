//
//  ShackLayoutTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Ham shack layout")
struct ShackLayoutTests {

	private static let now = Date(timeIntervalSince1970: 2_000_000_000)
	private static let grid = ShackRackGrid(columns: 10, rows: 10, pitch: 0.1)

	private func node(_ id: Int64, online: Bool = true, favorite: Bool = false, connected: Bool = false) -> ShackNodeSnapshot {
		ShackNodeSnapshot(
			id: id, shortName: "N\(id)", longName: "Node \(id)", hwModel: nil, hardwareName: nil, role: nil,
			lastHeard: online ? Self.now : Self.now.addingTimeInterval(-3 * 60 * 60),
			isOnline: online, isFavorite: favorite, viaMqtt: false, isConnectedRadio: connected,
			hopsAway: 1, snr: 5, rssi: -80, hasPosition: false
		)
	}

	/// The connected radio, then `favorites` favorites, then online nodes, then offline ones.
	private func mesh(count: Int, favorites: Int = 2, online: Int) -> [ShackNodeSnapshot] {
		(0..<count).map { index in
			node(Int64(index + 1), online: index < online, favorite: index >= 1 && index <= favorites, connected: index == 0)
		}
	}

	private func tiers(_ layout: ShackLayout) -> [ShackTier: Int] {
		layout.slots.values.reduce(into: [:]) { $0[$1.tier, default: 0] += 1 }
	}

	@Test("Ten nodes: the radio on the desk, favorites beside it, online nodes on the shelves, the rest in the rack")
	func tenNodes() {
		var layout = ShackLayout(grid: Self.grid)
		layout.update(mesh(count: 10, online: 6), now: Self.now)
		#expect(layout.slots[1] == .deskRadio)
		#expect(layout.slots[2] == .desk(0))
		#expect(layout.slots[3] == .desk(1))
		#expect(tiers(layout) == [.deskRadio: 1, .desk: 2, .shelf: 3, .rack: 4])
		#expect(layout.overflow == 0)
		#expect(layout.rackPageCount == 1)
	}

	@Test("Fifty nodes fill the shelves before the rack")
	func fiftyNodes() {
		var layout = ShackLayout(grid: Self.grid)
		layout.update(mesh(count: 50, favorites: 6, online: 40), now: Self.now)
		#expect(layout.slots[1] == .deskRadio)
		#expect(tiers(layout) == [.deskRadio: 1, .desk: 4, .shelf: ShackLayout.shelfCapacity, .rack: 50 - 29])
		// The two favorites past the desk's four go on the shelves first.
		#expect(layout.slots[6]?.tier == .shelf)
		#expect(layout.slots[7]?.tier == .shelf)
	}

	@Test("Five hundred nodes page through the rack and overflow when it is full")
	func fiveHundredNodes() {
		var layout = ShackLayout(grid: Self.grid, maxRackPages: 4)
		layout.update(mesh(count: 500, online: 300), now: Self.now)
		#expect(layout.slots[1] == .deskRadio)
		#expect(layout.rackPageCount == 4)
		#expect(tiers(layout)[.rack] == 400)
		#expect(layout.overflow == 500 - 400 - 1 - 2 - ShackLayout.shelfCapacity)
		#expect(layout.rackPage(0).count == 100)
		#expect(layout.rackPage(3).count == 100)

		var roomy = ShackLayout(grid: Self.grid, maxRackPages: 6)
		roomy.update(mesh(count: 500, online: 300), now: Self.now)
		#expect(roomy.overflow == 0)
		#expect(roomy.rackPageCount == 5)
	}

	@Test("The desk follows the connected radio at once")
	func deskFollowsConnection() {
		var layout = ShackLayout(grid: Self.grid)
		var nodes = mesh(count: 10, online: 10)
		layout.update(nodes, now: Self.now)
		#expect(layout.slots[1] == .deskRadio)
		nodes[0] = node(1, online: true)
		nodes[5] = node(6, online: true, connected: true)
		layout.update([nodes[5]] + nodes.filter { $0.id != 6 }, now: Self.now.addingTimeInterval(5))
		#expect(layout.slots[6] == .deskRadio)
		#expect(layout.slots[1] != .deskRadio)
	}

	@Test("Nodes keep their places, and a new node takes the first free one")
	func stickySlots() {
		var layout = ShackLayout(grid: Self.grid)
		let nodes = mesh(count: 60, online: 20)
		layout.update(nodes, now: Self.now)
		let before = layout.slots
		// Drop one rack node and reverse the rest of the order: nobody else moves.
		let dropped = Int64(45)
		guard case .rack(let freed) = before[dropped] else {
			Issue.record("Node \(dropped) should be in the rack")
			return
		}
		var reordered = Array(nodes.filter { $0.id != dropped }.reversed())
		reordered.removeAll { $0.id == 1 }
		reordered.insert(nodes[0], at: 0)
		layout.update(reordered, now: Self.now.addingTimeInterval(5))
		for (num, slot) in before where num != dropped {
			#expect(layout.slots[num] == slot)
		}
		layout.update(reordered + [node(999, online: false)], now: Self.now.addingTimeInterval(10))
		#expect(layout.slots[999] == .rack(freed))
	}

	@Test("Tier changes wait for the promotion interval")
	func promotionInterval() {
		var layout = ShackLayout(grid: Self.grid)
		var nodes = mesh(count: 10, favorites: 0, online: 9)
		layout.update(nodes, now: Self.now)
		#expect(layout.slots[10]?.tier == .rack)
		// Node 10 becomes a favorite: it waits for the next promotion to reach the desk.
		nodes[9] = node(10, online: false, favorite: true)
		let reordered = [nodes[0], nodes[9]] + nodes[1..<9]
		layout.update(Array(reordered), now: Self.now.addingTimeInterval(10))
		#expect(layout.slots[10]?.tier == .rack)
		layout.update(Array(reordered), now: Self.now.addingTimeInterval(ShackLayout.promotionInterval))
		#expect(layout.slots[10] == .desk(0))
	}

	@Test("A full shelf keeps its nodes when last-heard order changes")
	func fullShelfStaysPut() {
		var layout = ShackLayout(grid: Self.grid)
		let nodes = mesh(count: 60, favorites: 0, online: 40)
		layout.update(nodes, now: Self.now)
		let shelved = Set(layout.slots.filter { $0.value.tier == .shelf }.keys)
		#expect(shelved.count == ShackLayout.shelfCapacity)
		// The online nodes on the rack are now heard more recently than those on the shelves.
		let online = nodes[1..<40]
		let reordered = [nodes[0]] + online.filter { !shelved.contains($0.id) } + online.filter { shelved.contains($0.id) } + nodes[40...]
		layout.update(reordered, now: Self.now.addingTimeInterval(ShackLayout.promotionInterval))
		#expect(Set(layout.slots.filter { $0.value.tier == .shelf }.keys) == shelved)
	}

	@Test("Online and offline change only after the hysteresis")
	func hysteresis() {
		var layout = ShackLayout(grid: Self.grid)
		layout.update([node(1, online: true)], now: Self.now)
		#expect(layout.isOnline(1))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(10))
		#expect(layout.isOnline(1))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(10 + ShackLayout.hysteresis - 1))
		#expect(layout.isOnline(1))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(10 + ShackLayout.hysteresis))
		#expect(!layout.isOnline(1))
		// A blip back online that doesn't last resets nothing.
		layout.update([node(1, online: true)], now: Self.now.addingTimeInterval(400))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(410))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(530))
		#expect(!layout.isOnline(1))
	}

	@Test("The room's rack grid keeps cells about 6% of the viewing distance and finds the cell under a point")
	func rackGrid() {
		let grid = ShackRackGrid.forRoom(rack: ShackRoomGeometry.defaultPose(.wallRack))
		let distance = simd_distance(ShackRoomGeometry.seatedEye, ShackRoomGeometry.defaultPose(.wallRack).position)
		#expect(grid.pitch >= 0.06 * distance)
		#expect(Float(grid.columns) * grid.pitch <= ShackRoomGeometry.rackSize.x)
		#expect(Float(grid.rows) * grid.pitch <= ShackRoomGeometry.rackSize.y)
		#expect(grid.perPage > 100)
		for index in [0, grid.columns - 1, grid.perPage / 2, grid.perPage - 1] {
			#expect(grid.cell(at: grid.center(ofCellOnPage: index)) == index)
		}
		#expect(grid.cell(at: SIMD2(10, 0)) == nil)
		#expect(grid.center(ofCellOnPage: 0).y > 0)
	}

	@Test("Shelf places sit on their shelf, spread across it")
	func placement() {
		let grid = ShackRackGrid.forRoom(rack: ShackRoomGeometry.defaultPose(.wallRack))
		let first = ShackPlacement.pose(of: .shelf(1, 0), grid: grid, anchor: ShackRoomGeometry.defaultPose)
		let last = ShackPlacement.pose(of: .shelf(1, ShackLayout.perShelf - 1), grid: grid, anchor: ShackRoomGeometry.defaultPose)
		#expect(first.position.y == ShackRoomGeometry.defaultPose(.shelf1).position.y)
		#expect(last.position.x - first.position.x > ShackRoomGeometry.shelfLength * 0.8)
		let rack = ShackPlacement.pose(of: .rack(0), grid: grid, anchor: ShackRoomGeometry.defaultPose)
		// The rack is on the right wall, so its cells share the anchor's x.
		#expect(abs(rack.position.x - ShackRoomGeometry.defaultPose(.wallRack).position.x) < 1e-4)
	}
}
