//
//  LookoutMarkerTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("Fire lookout node markers")
struct LookoutMarkerTests {

	@Test("a marker stands a short stem above its node")
	func shortStem() {
		let center = LookoutMarkerGrouping.center(elevation: 2)
		#expect(abs(center - 2 - LookoutMarkerGrouping.stemDegrees - LookoutMarkerGrouping.markerWidthDegrees / 2) < 1e-9)
	}

	@Test("a node below the view gets a marker at the bottom of it, on the same short stem")
	func valleyNode() {
		#expect(LookoutMarkerGrouping.center(elevation: -30) == LookoutMarkerGrouping.center(elevation: LookoutMarkerGrouping.lowestMarkerDegrees))
	}

	@Test("nodes whose markers would overlap share one, standing over the nearest")
	func overlapping() {
		let groups = LookoutMarkerGrouping.groups([(100, 0.5), (101, 0.3), (100.5, 1.2)])
		#expect(groups == [[0, 1, 2]])
	}

	@Test("nodes apart in bearing, or one far above the other, get markers of their own")
	func apart() {
		#expect(LookoutMarkerGrouping.groups([(100, 0), (110, 0)]) == [[0], [1]])
		#expect(LookoutMarkerGrouping.groups([(100, 0), (100, 8)]) == [[0], [1]])
	}

	@Test("nodes either side of the cab's front are still close")
	func acrossFront() {
		#expect(LookoutMarkerGrouping.groups([(359.5, 0), (0.5, 0)]) == [[0, 1]])
	}

	@Test("valley nodes far below one another share the marker at the bottom of the view")
	func valley() {
		#expect(LookoutMarkerGrouping.groups([(50, -10), (50.5, -25)]) == [[0, 1]])
	}

	@Test("a node joins the first marker it overlaps, not a later one")
	func joinsFirst() {
		#expect(LookoutMarkerGrouping.groups([(100, 0), (103, 0), (101.5, 0)]) == [[0, 2], [1]])
	}
}
