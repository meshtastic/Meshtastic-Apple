// MapColocatedItemsTests.swift
// MeshtasticTests
//
// Coverage for the mesh map's UNIFIED coincident-item grouping over `MeshMapItem`
// (`MeshMapItem.colocated(with:in:withinMeters:)` + `MeshMapItem.dedupedSortedForPicker(_:)`).
//
// Since waypoints now cluster with nodes (both are `MeshMapItem`s sharing one clustering identifier),
// the "Select an Item" picker can contain nodes AND waypoints. These tests pin the mixed-scene
// grouping, the node/waypoint id-namespace separation (a node and a waypoint that share a raw id must
// NOT collide into one picker row), and the picker ordering.

import Testing
import Foundation
import CoreLocation
@testable import Meshtastic

@Suite("Map colocated-item (node + waypoint) grouping")
struct MapColocatedItemsTests {

	private static let baseLat = 47.6001
	private static let baseLon = -122.3301
	/// The production threshold, referenced (not re-hardcoded) so the tests track the single source of
	/// truth and offsets stay valid if it changes.
	private static let spread = MapColocation.spreadMeters

	private func nodeItem(_ nodeNum: Int64, lat: Double = baseLat, lon: Double = baseLon, name: String? = nil) -> MeshMapItem {
		.node(MeshMapPositionSnapshot(
			id: nodeNum,
			coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
			latitudeI: Int32(lat * 1e7),
			longitudeI: Int32(lon * 1e7),
			precisionBits: 32,
			nodeNum: nodeNum,
			longName: name ?? "Node \(nodeNum)",
			shortName: "\(nodeNum)",
			isOnline: true,
			viaMqtt: false,
			calculatedDelay: 0
		))
	}

	private func waypointItem(_ id: Int64, lat: Double = baseLat, lon: Double = baseLon, name: String? = nil, icon: String = "📍") -> MeshMapItem {
		.waypoint(MeshMapWaypointSnapshot(
			id: id,
			coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
			name: name ?? "Waypoint \(id)",
			icon: icon
		))
	}

	/// A coordinate offset `meters` due north of the base point (1° latitude ≈ 111_320 m).
	private func north(_ meters: Double) -> (lat: Double, lon: Double) {
		(Self.baseLat + meters / 111_320.0, Self.baseLon)
	}

	// MARK: - Mixed membership

	@Test("A waypoint coincident with a node groups with it")
	func waypointGroupsWithNode() {
		let node = nodeItem(1)
		let waypoint = waypointItem(1) // same point, raw id collides with the node num on purpose
		let result = MeshMapItem.colocated(with: node, in: [node, waypoint], withinMeters: Self.spread)
		#expect(Set(result.map(\.id)) == [.node(1), .waypoint(1)])
	}

	@Test("A waypoint beyond the threshold is excluded")
	func distantWaypointExcluded() {
		let node = nodeItem(1)
		let far = north(Self.spread * 1.2)
		let waypoint = waypointItem(9, lat: far.lat, lon: far.lon)
		let result = MeshMapItem.colocated(with: node, in: [node, waypoint], withinMeters: Self.spread)
		#expect(result.map(\.id) == [.node(1)])
	}

	@Test("Tapping a waypoint pulls in its coincident nodes (occluded-marker reachability)")
	func waypointTapGroupsNodes() {
		let waypoint = waypointItem(5)
		let nodeA = nodeItem(1)
		let nodeB = nodeItem(2)
		let result = MeshMapItem.colocated(with: waypoint, in: [waypoint, nodeA, nodeB], withinMeters: Self.spread)
		#expect(Set(result.map(\.id)) == [.waypoint(5), .node(1), .node(2)])
	}

	@Test("Grouping is scoped to the tapped marker's neighborhood, not the whole scene")
	func neighborhoodScoped() {
		let stackA: [MeshMapItem] = [nodeItem(1), waypointItem(1)]
		let farPoint = north(50)
		let stackB: [MeshMapItem] = [
			nodeItem(2, lat: farPoint.lat, lon: farPoint.lon),
			waypointItem(2, lat: farPoint.lat, lon: farPoint.lon)
		]
		let scene = stackA + stackB
		let resultA = MeshMapItem.colocated(with: stackA[0], in: scene, withinMeters: Self.spread)
		#expect(Set(resultA.map(\.id)) == [.node(1), .waypoint(1)])
	}

	// MARK: - Picker de-duplication (id namespace)

	@Test("A node and a waypoint sharing a raw id are two distinct picker rows")
	func nodeAndWaypointDoNotCollide() {
		// Node num 7 and waypoint id 7 — different ID cases, so both must survive de-dup.
		let items = [nodeItem(7), waypointItem(7)]
		let result = MeshMapItem.dedupedSortedForPicker(items)
		#expect(result.count == 2)
		#expect(Set(result.map(\.id)) == [.node(7), .waypoint(7)])
	}

	@Test("Duplicate node nums collapse but a coincident waypoint stays")
	func duplicateNodesCollapseWaypointStays() {
		// Two nil-node positions both num 0, plus a real waypoint at the same point.
		let items = [nodeItem(0), nodeItem(0), waypointItem(3)]
		let result = MeshMapItem.dedupedSortedForPicker(items)
		#expect(Set(result.map(\.id)) == [.node(0), .waypoint(3)]) // one node row, one waypoint row
	}

	@Test("Duplicate waypoint ids collapse to one row")
	func duplicateWaypointsCollapse() {
		let items = [waypointItem(4), waypointItem(4)]
		let result = MeshMapItem.dedupedSortedForPicker(items)
		#expect(result.map(\.id) == [.waypoint(4)])
	}

	// MARK: - Ordering

	@Test("Picker input is sorted by display name across nodes and waypoints")
	func sortsMixedByName() {
		let zebra = nodeItem(1, name: "Zebra")
		let apple = waypointItem(2, name: "Apple")
		let mango = nodeItem(3, name: "Mango")
		let result = MeshMapItem.dedupedSortedForPicker([zebra, apple, mango])
		#expect(result.map(\.displayName) == ["Apple", "Mango", "Zebra"])
	}

	// MARK: - Decision semantics (count > 1 -> picker)

	@Test("A lone node with only distant waypoints selects directly (no picker)")
	func loneNodeDirectSelect() {
		let node = nodeItem(1)
		let far = north(30)
		let waypoint = waypointItem(2, lat: far.lat, lon: far.lon)
		let result = MeshMapItem.colocated(with: node, in: [node, waypoint], withinMeters: Self.spread)
		#expect(result.count == 1) // count == 1 -> open directly, not the picker
	}

	@Test("A node stacked with a waypoint drives the picker")
	func stackedDrivesPicker() {
		let node = nodeItem(1)
		let waypoint = waypointItem(2)
		let result = MeshMapItem.dedupedSortedForPicker(
			MeshMapItem.colocated(with: node, in: [node, waypoint], withinMeters: Self.spread)
		)
		#expect(result.count > 1) // count > 1 -> present the "Select an Item" picker
	}
}
