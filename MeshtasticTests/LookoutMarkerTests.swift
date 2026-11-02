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

	private typealias Grouping = LookoutMarkerGrouping

	@Test("a marker stands a stem above its node")
	func stem() {
		let markers = Grouping.markers([(100, 2)])
		#expect(markers == [Grouping.Marker(members: [0], center: Grouping.center(elevation: 2))])
		#expect(abs(Grouping.center(elevation: 2) - 2 - Grouping.stemDegrees - Grouping.markerWidthDegrees / 2) < 1e-9)
		#expect(Grouping.stemFoot(elevation: 2) == 2)
	}

	@Test("a node below the view gets a marker at the bottom of it")
	func valleyNode() {
		#expect(Grouping.center(elevation: -30) == Grouping.center(elevation: Grouping.lowestMarkerDegrees))
		#expect(Grouping.stemFoot(elevation: -30) == Grouping.lowestMarkerDegrees)
	}

	@Test("a node whose marker would cover one already placed gets its own on a taller stem")
	func raised() {
		let markers = Grouping.markers([(100, 0), (100.5, 0)])
		#expect(markers.map(\.members) == [[0], [1]])
		#expect(abs(markers[1].center - markers[0].center - Grouping.markerWidthDegrees) < 1e-9)
	}

	@Test("a raised marker takes the lowest height that's clear")
	func lowestClear() {
		// The second sits a height up; the third, beside the second but clear of the first, stays low.
		let markers = Grouping.markers([(100, 0), (101, 0), (102.2, 0)])
		#expect(markers.map(\.members) == [[0], [1], [2]])
		#expect(markers[2].center == Grouping.center(elevation: 0))
	}

	@Test("nodes share a marker only when every height is taken")
	func shareWhenFull() {
		let points = (0..<4).map { (azimuth: 100 + Double($0) * 0.1, elevation: 0.0) }
		let markers = Grouping.markers(points)
		#expect(markers.count == Grouping.levels)
		#expect(markers[0].members == [0, 3])
	}

	@Test("markers apart in bearing all stand at their own height")
	func apart() {
		let markers = Grouping.markers([(100, 0), (110, 0), (120, 0)])
		#expect(markers.allSatisfy { $0.center == Grouping.center(elevation: 0) })
	}

	@Test("markers either side of the cab's front are still close")
	func acrossFront() {
		let markers = Grouping.markers([(359.5, 0), (0.5, 0)])
		#expect(markers[1].center > markers[0].center)
	}
}
