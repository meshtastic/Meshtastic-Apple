// MapColocatedNodesTests.swift
// MeshtasticTests
//
// Coverage for the map's coincident-node disambiguation grouping
// (`MeshMapPositionSnapshot.colocated(with:in:withinMeters:)`).
//
// This is the pure policy behind the "Select a Node" picker: when map clustering is OFF, MapKit
// forms no cluster annotation, so a pin tap lands only on the topmost of a set of overlapping pins.
// Grouping the tapped node with its coincident neighbors is what keeps the occluded nodes reachable
// (the map presents the picker when the group has more than one member).

import Testing
import Foundation
import CoreLocation
@testable import Meshtastic

@Suite("Map colocated-node grouping")
struct MapColocatedNodesTests {

	/// ~1.1132 m of latitude per 0.00001°, at the test latitude. Handy for building known offsets.
	private static let baseLat = 47.6001
	private static let baseLon = -122.3301
	/// The production threshold, referenced (not re-hardcoded) so the tests track the single source of
	/// truth and offsets stay valid if it changes.
	private static let spread = MapColocation.spreadMeters

	private func snapshot(_ nodeNum: Int64, lat: Double, lon: Double) -> MeshMapPositionSnapshot {
		MeshMapPositionSnapshot(
			id: nodeNum,
			coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
			latitudeI: Int32(lat * 1e7),
			longitudeI: Int32(lon * 1e7),
			precisionBits: 32,
			nodeNum: nodeNum,
			longName: "Node \(nodeNum)",
			shortName: "\(nodeNum)",
			isOnline: true,
			viaMqtt: false,
			calculatedDelay: 0
		)
	}

	/// A node offset `meters` due north of the base point.
	private func northOffset(_ nodeNum: Int64, meters: Double) -> MeshMapPositionSnapshot {
		// 1° latitude ≈ 111_320 m.
		snapshot(nodeNum, lat: Self.baseLat + meters / 111_320.0, lon: Self.baseLon)
	}

	private func base(_ nodeNum: Int64) -> MeshMapPositionSnapshot {
		snapshot(nodeNum, lat: Self.baseLat, lon: Self.baseLon)
	}

	// MARK: - Membership

	@Test("A lone node returns only itself")
	func loneNode() {
		let origin = base(1)
		let result = MeshMapPositionSnapshot.colocated(with: origin, in: [origin], withinMeters: Self.spread)
		#expect(result.count == 1)
		#expect(result.first?.nodeNum == 1)
	}

	@Test("Origin is always included, even with distant others")
	func originAlwaysIncluded() {
		let origin = base(1)
		let far = northOffset(2, meters: 50)
		let result = MeshMapPositionSnapshot.colocated(with: origin, in: [origin, far], withinMeters: Self.spread)
		#expect(result.map(\.nodeNum) == [1])
	}

	@Test("Exactly coincident pair groups both")
	func exactlyCoincidentPair() {
		let a = base(1)
		let b = base(2) // identical coordinate
		let result = MeshMapPositionSnapshot.colocated(with: a, in: [a, b], withinMeters: Self.spread)
		#expect(Set(result.map(\.nodeNum)) == [1, 2])
	}

	@Test("Ten exactly-coincident nodes all group")
	func tenCoincident() {
		let nodes = (1...10).map { base(Int64($0)) }
		let result = MeshMapPositionSnapshot.colocated(with: nodes[0], in: nodes, withinMeters: Self.spread)
		#expect(result.count == 10)
	}

	@Test("Sub-meter near-coincident pair (GPS jitter / precision fuzz) groups")
	func subMeterPairGroups() {
		// ~0.11 m apart — the boundary-straddling "pairs" case that used to escape same-cell grouping.
		let a = snapshot(1, lat: 47.6000045, lon: -122.33000)
		let b = snapshot(2, lat: 47.6000055, lon: -122.33000)
		let result = MeshMapPositionSnapshot.colocated(with: a, in: [a, b], withinMeters: Self.spread)
		#expect(Set(result.map(\.nodeNum)) == [1, 2])
	}

	// MARK: - Threshold behavior

	@Test("A node within the threshold is included")
	func withinThreshold() {
		let origin = base(1)
		let near = northOffset(2, meters: Self.spread * 0.8) // comfortably inside
		let result = MeshMapPositionSnapshot.colocated(with: origin, in: [origin, near], withinMeters: Self.spread)
		#expect(Set(result.map(\.nodeNum)) == [1, 2])
	}

	@Test("A node beyond the threshold is excluded")
	func beyondThreshold() {
		let origin = base(1)
		let far = northOffset(2, meters: Self.spread * 1.2) // comfortably outside
		let result = MeshMapPositionSnapshot.colocated(with: origin, in: [origin, far], withinMeters: Self.spread)
		#expect(result.map(\.nodeNum) == [1])
	}

	@Test("The threshold is strict: a node just past it is excluded, just inside is included")
	func strictThresholdBoundary() {
		let origin = base(1)
		// Bracket the threshold tightly (±1 cm) to pin the `<` (not `<=`) comparison.
		let justInside = northOffset(2, meters: Self.spread - 0.01)
		let justOutside = northOffset(3, meters: Self.spread + 0.01)
		let result = MeshMapPositionSnapshot.colocated(with: origin, in: [origin, justInside, justOutside], withinMeters: Self.spread)
		#expect(Set(result.map(\.nodeNum)) == [1, 2])
	}

	@Test("An empty snapshot list returns nothing (no crash, no phantom origin)")
	func emptySnapshots() {
		let origin = base(1)
		// The origin isn't in the list, so it isn't returned; the map only ever calls this with the
		// tapped node present in `visiblePositionSnapshots`, but the helper must be total.
		#expect(MeshMapPositionSnapshot.colocated(with: origin, in: [], withinMeters: Self.spread).isEmpty)
	}

	@Test("A wider custom threshold groups nodes that the default would exclude")
	func customThreshold() {
		let origin = base(1)
		let node = northOffset(2, meters: 6) // excluded at 5 m, included at 10 m
		#expect(MeshMapPositionSnapshot.colocated(with: origin, in: [origin, node], withinMeters: 5.0).count == 1)
		#expect(MeshMapPositionSnapshot.colocated(with: origin, in: [origin, node], withinMeters: 10.0).count == 2)
	}

	// MARK: - Mixed scenes

	@Test("Only the coincident members of a mixed scene are returned")
	func mixedScene() {
		// Three coincident at base, plus two clearly separate nodes.
		let stack = [base(1), base(2), base(3)]
		let farA = northOffset(4, meters: 40)
		let farB = northOffset(5, meters: 80)
		let scene = stack + [farA, farB]
		let result = MeshMapPositionSnapshot.colocated(with: stack[0], in: scene, withinMeters: Self.spread)
		#expect(Set(result.map(\.nodeNum)) == [1, 2, 3])
	}

	@Test("Grouping is scoped to the tapped node's neighborhood, not the whole scene")
	func neighborhoodScoped() {
		// Two distinct coincident stacks ~50 m apart; tapping one must not pull in the other.
		let stackA = [base(1), base(2)]
		let stackB = [northOffset(3, meters: 50), northOffset(4, meters: 50)]
		let scene = stackA + stackB
		let resultA = MeshMapPositionSnapshot.colocated(with: stackA[0], in: scene, withinMeters: Self.spread)
		#expect(Set(resultA.map(\.nodeNum)) == [1, 2])
		let resultB = MeshMapPositionSnapshot.colocated(with: stackB[0], in: scene, withinMeters: Self.spread)
		#expect(Set(resultB.map(\.nodeNum)) == [3, 4])
	}

	// MARK: - Decision semantics
	//
	// The map opens the disambiguation picker exactly when the group has more than one member, and
	// otherwise selects the single node. These assertions pin that "count > 1" contract so the two
	// call sites (clustering-on cluster tap and clustering-off pin tap) stay consistent.

	@Test("Group of one drives a direct selection (no picker)")
	func singleMemberMeansDirectSelect() {
		let origin = base(1)
		let result = MeshMapPositionSnapshot.colocated(with: origin, in: [origin, northOffset(2, meters: 30)], withinMeters: Self.spread)
		#expect(result.count == 1) // count == 1 → selectNode, not the picker
	}

	@Test("Group of many drives the picker")
	func manyMembersMeanPicker() {
		let nodes = [base(1), base(2)]
		let result = MeshMapPositionSnapshot.colocated(with: nodes[0], in: nodes, withinMeters: Self.spread)
		#expect(result.count > 1) // count > 1 → present the "Select a Node" picker
	}

	// MARK: - Picker ordering / de-duplication
	//
	// `dedupedByNodeNumSortedByName` is what the map feeds the picker's `List`, whose row identity is
	// `snapshot.id` (== `nodeNum`). Duplicate nums would collide into duplicate List IDs.

	@Test("Picker input is de-duplicated by nodeNum")
	func dedupesByNodeNum() {
		// Two snapshots sharing nodeNum 0 (positions whose node is nil) plus a distinct node.
		let dupA = snapshot(0, lat: Self.baseLat, lon: Self.baseLon)
		let dupB = snapshot(0, lat: Self.baseLat, lon: Self.baseLon)
		let other = snapshot(7, lat: Self.baseLat, lon: Self.baseLon)
		let result = MeshMapPositionSnapshot.dedupedByNodeNumSortedByName([dupA, dupB, other])
		#expect(result.map(\.nodeNum) == [0, 7]) // one row per num, no collision
	}

	@Test("Coincident duplicates of one node collapse to a single selectable entry")
	func coincidentDuplicatesCollapse() {
		// Two snapshots for the SAME nodeNum at the same point (e.g. duplicate/nil-node positions).
		let a = snapshot(5, lat: Self.baseLat, lon: Self.baseLon)
		let b = snapshot(5, lat: Self.baseLat, lon: Self.baseLon)
		let coincident = MeshMapPositionSnapshot.colocated(with: a, in: [a, b], withinMeters: Self.spread)
		#expect(coincident.count == 2) // both fall within range...
		let pickerReady = MeshMapPositionSnapshot.dedupedByNodeNumSortedByName(coincident)
		#expect(pickerReady.count == 1) // ...but they are one node, so no picker (count 1 -> direct select)
	}

	@Test("Picker input is sorted by display name")
	func sortsByName() {
		let charlie = snapshot(1, lat: Self.baseLat, lon: Self.baseLon) // longName "Node 1"
		let alpha = MeshMapPositionSnapshot(
			id: 2, coordinate: CLLocationCoordinate2D(latitude: Self.baseLat, longitude: Self.baseLon),
			latitudeI: 0, longitudeI: 0, precisionBits: 32, nodeNum: 2,
			longName: "Aardvark", shortName: "A", isOnline: true, viaMqtt: false, calculatedDelay: 0
		)
		let result = MeshMapPositionSnapshot.dedupedByNodeNumSortedByName([charlie, alpha])
		#expect(result.map(\.longName) == ["Aardvark", "Node 1"])
	}
}
