//
//  RooftopSitesTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//
import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

@Suite("City rooftop sites")
struct RooftopSitesTests {

	private let center = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)

	/// A square `side` meters across, centered `east` and `north` meters from the center.
	private func square(side: Double, east: Double = 0, north: Double = 0, height: Double?) -> SpatialBuildingFootprint {
		let metersPerLat = SpatialFrame.metersPerDegreeLatitude
		let metersPerLon = metersPerLat * cos(center.latitude * .pi / 180)
		let corners: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
		let outline = corners.map { x, y in
			CLLocationCoordinate2D(latitude: center.latitude + (north + y * side / 2) / metersPerLat, longitude: center.longitude + (east + x * side / 2) / metersPerLon)
		}
		return SpatialBuildingFootprint(outline: outline, height: height, minHeight: 0)
	}

	@Test("the tallest buildings come first, and buildings with no height are left out")
	func tallestFirst() {
		let rooftops = RooftopSites.tallest([
			square(side: 40, east: 0, height: 80),
			square(side: 40, east: 600, height: 200),
			square(side: 40, east: -600, height: 120),
			square(side: 40, east: 1_200, height: nil)
		])
		#expect(rooftops.map(\.height) == [200, 120, 80])
	}

	@Test("a building beside a taller one is the same tower, and is left out")
	func nearTallerIsSameTower() {
		let rooftops = RooftopSites.tallest([
			square(side: 40, height: 180),
			// The podium, 60 m off the tower's middle.
			square(side: 40, east: 60, height: 40),
			square(side: 40, east: 400, height: 90)
		])
		#expect(rooftops.map(\.height) == [180, 90])
	}

	@Test("a roof too small to stand on, like a spire's, is left out")
	func spiresAreLeftOut() {
		let rooftops = RooftopSites.tallest([
			square(side: 6, height: 300),
			square(side: 30, east: 500, height: 150)
		])
		#expect(rooftops.map(\.height) == [150])
	}

	@Test("no more than the count asked for, and each rooftop is on its roof")
	func countAndPlace() {
		let footprints = (0..<20).map { square(side: 30, east: Double($0) * 300, height: Double(50 + $0)) }
		let rooftops = RooftopSites.tallest(footprints, count: 5)
		#expect(rooftops.count == 5)
		#expect(rooftops.first?.height == 69)
		for rooftop in rooftops {
			#expect(footprints.contains { SpatialBuildings.contains($0.outline, rooftop.coordinate) && $0.height == rooftop.height })
		}
	}

	@Test("a roof's area is measured in square meters")
	func roofArea() {
		#expect(abs(RooftopSites.roofArea(square(side: 20, height: 10).outline) - 400) < 4)
		#expect(RooftopSites.roofArea([center]) == 0)
	}
}
