//
//  ShowcaseLayoutTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Showcase layout")
struct ShowcaseLayoutTests {

	private static let now = Date(timeIntervalSince1970: 2_000_000_000)
	private static let grid = ShowcaseRackGrid(columns: 10, rows: 10, pitch: 0.1)

	private func node(_ id: Int64, online: Bool = true, favorite: Bool = false, connected: Bool = false) -> ShowcaseNodeSnapshot {
		ShowcaseNodeSnapshot(
			id: id, shortName: "N\(id)", longName: "Node \(id)", hwModel: nil, hardwareName: nil, role: nil,
			lastHeard: online ? Self.now : Self.now.addingTimeInterval(-3 * 60 * 60),
			isOnline: online, isFavorite: favorite, viaMqtt: false, isConnectedRadio: connected,
			hopsAway: 1, snr: 5, rssi: -80, hasPosition: false
		)
	}

	/// The connected radio, then `favorites` favorites, then online nodes, then offline ones.
	///
	/// The closure is annotated and each argument hoisted into its own `let`. Written as one
	/// expression — three inferred comparisons and an `Int64` conversion feeding a call with
	/// four defaulted parameters — the type checker ran past its budget and the test target
	/// failed to build rather than failing a test.
	private func mesh(count: Int, favorites: Int = 2, online: Int) -> [ShowcaseNodeSnapshot] {
		(0..<count).map { (index: Int) -> ShowcaseNodeSnapshot in
			let isOnline: Bool = index < online
			let isFavorite: Bool = index >= 1 && index <= favorites
			let isConnected: Bool = index == 0
			return node(Int64(index + 1), online: isOnline, favorite: isFavorite, connected: isConnected)
		}
	}

	@Test("Ten nodes, the connected radio included, all go into the rack in order")
	func tenNodes() {
		var layout = ShowcaseLayout(grid: Self.grid)
		layout.update(mesh(count: 10, online: 6), now: Self.now)
		#expect(layout.slots[1] == .rack(0))
		#expect(layout.slots[2] == .rack(1))
		#expect(layout.slots.count == 10)
		#expect(layout.overflow == 0)
		#expect(layout.rackPageCount == 1)
	}

	@Test("A node that becomes the connected radio on a full rack takes the last node's place")
	func connectedRadioOnFullRack() {
		var layout = ShowcaseLayout(grid: Self.grid, maxRackPages: 1)
		var nodes = mesh(count: 120, online: 120)
		layout.update(nodes, now: Self.now)
		#expect(layout.slots[110] == nil)
		let last = Int64(100)
		#expect(layout.slots[last] != nil)
		// Connect to node 110, which overflowed; the reader puts it first.
		nodes = nodes.filter { $0.id != 110 }.map { node($0.id, connected: false) }
		nodes.insert(node(110, connected: true), at: 0)
		let before = layout.slots
		layout.update(nodes, now: Self.now)
		#expect(layout.slots[110] == before[last])
		#expect(layout.slots[last] == nil)
		#expect(layout.overflow == 20)
		// Everyone else keeps their place.
		for (num, slot) in before where num != last { #expect(layout.slots[num] == slot) }
	}

	@Test("Five hundred nodes page through the rack and overflow when it is full")
	func fiveHundredNodes() {
		var layout = ShowcaseLayout(grid: Self.grid, maxRackPages: 4)
		layout.update(mesh(count: 500, online: 300), now: Self.now)
		#expect(layout.slots[1] == .rack(0))
		#expect(layout.rackPageCount == 4)
		#expect(layout.slots.count == 400)
		#expect(layout.overflow == 500 - 400)
		#expect(layout.rackPage(0).count == 100)
		#expect(layout.rackPage(3).count == 100)

		var roomy = ShowcaseLayout(grid: Self.grid, maxRackPages: 6)
		roomy.update(mesh(count: 500, online: 300), now: Self.now)
		#expect(roomy.overflow == 0)
		#expect(roomy.rackPageCount == 5)
	}

	@Test("Nodes keep their places, and a new node takes the first free one")
	func stickySlots() {
		var layout = ShowcaseLayout(grid: Self.grid)
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

	@Test("Online and offline change only after the hysteresis")
	func hysteresis() {
		var layout = ShowcaseLayout(grid: Self.grid)
		layout.update([node(1, online: true)], now: Self.now)
		#expect(layout.isOnline(1))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(10))
		#expect(layout.isOnline(1))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(10 + ShowcaseLayout.hysteresis - 1))
		#expect(layout.isOnline(1))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(10 + ShowcaseLayout.hysteresis))
		#expect(!layout.isOnline(1))
		// A blip back online that doesn't last resets nothing.
		layout.update([node(1, online: true)], now: Self.now.addingTimeInterval(400))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(410))
		layout.update([node(1, online: false)], now: Self.now.addingTimeInterval(530))
		#expect(!layout.isOnline(1))
	}

	@Test("The room's rack grid keeps cells about 6% of the viewing distance and finds the cell under a point")
	func rackGrid() {
		let grid = ShowcaseRackGrid.forRoom(rack: ShowcaseRoomGeometry.defaultPose(.wallRack))
		let distance = simd_distance(ShowcaseRoomGeometry.seatedEye, ShowcaseRoomGeometry.defaultPose(.wallRack).position)
		#expect(grid.pitch >= 0.06 * distance)
		#expect(Float(grid.columns) * grid.pitch <= ShowcaseRoomGeometry.rackSize.x)
		#expect(Float(grid.rows) * grid.pitch <= ShowcaseRoomGeometry.rackSize.y)
		// Hung on the back wall it is further away, so its cells are bigger and fewer.
		#expect(grid.perPage == 56) // four rows of 14
		for index in [0, grid.columns - 1, grid.perPage / 2, grid.perPage - 1] {
			#expect(grid.cell(at: grid.center(ofCellOnPage: index)) == index)
		}
		#expect(grid.cell(at: SIMD2(10, 0)) == nil)
		#expect(grid.center(ofCellOnPage: 0).y > 0)
	}

	@Test("Rack cells sit on the rack's wall")
	func placement() {
		let grid = ShowcaseRackGrid.forRoom(rack: ShowcaseRoomGeometry.defaultPose(.wallRack))
		let rack = ShowcasePlacement.pose(of: .rack(0), grid: grid, anchor: ShowcaseRoomGeometry.defaultPose)
		// The rack hangs on the back wall, so its cells share the anchor's depth.
		#expect(abs(rack.position.z - ShowcaseRoomGeometry.defaultPose(.wallRack).position.z) < 1e-4)
	}
}
