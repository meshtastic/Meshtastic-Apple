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

	@Test("a tower drawn only in parts, missing from the coarse first pass, wins over a shorter plain building beside it")
	func partsTowerFoundInSecondPass() throws {
		let plain = square(side: 40, east: -500, height: 260)
		var tier = square(side: 27, height: 286)
		tier.isPart = true
		var lowerTier = square(side: 35, height: 280)
		lowerTier.isPart = true
		let box = GeoBounds(minLon: center.longitude - 0.15, minLat: center.latitude - 0.1, maxLon: center.longitude + 0.15, maxLat: center.latitude + 0.1)
		var reads: [(GeoBounds, Int)] = []
		let rooftops = try #require(RooftopSites.search(in: box, maxTiles: 160) { bounds, maxTiles in
			reads.append((bounds, maxTiles))
			// The whole box is read coarsely, without the parts; a small box finely, with them.
			return bounds == box ? [plain] : [plain, tier, lowerTier]
		})
		#expect(rooftops.first?.height == 286)
		#expect(rooftops.map(\.height) == [286, 260])
		#expect(reads.count == 2)
		#expect(reads.last?.1 == RooftopSites.refineTiles)
	}

	@Test("boxes round neighboring rooftops are joined, and a rooftop far off keeps its own")
	func refineBoxesJoin() {
		let box = GeoBounds(minLon: center.longitude - 0.15, minLat: center.latitude - 0.1, maxLon: center.longitude + 0.15, maxLat: center.latitude + 0.1)
		let rooftops = RooftopSites.tallest([
			square(side: 40, height: 200),
			square(side: 40, east: 500, height: 180),
			square(side: 40, east: 8_000, height: 150)
		])
		let boxes = RooftopSites.refineBoxes(around: rooftops, within: box)
		#expect(boxes.count == 2)
		for rooftop in rooftops {
			#expect(boxes.contains { $0.minLat <= rooftop.coordinate.latitude && rooftop.coordinate.latitude <= $0.maxLat && $0.minLon <= rooftop.coordinate.longitude && rooftop.coordinate.longitude <= $0.maxLon })
		}
		#expect(boxes.allSatisfy { $0.minLon >= box.minLon && $0.maxLon <= box.maxLon && $0.minLat >= box.minLat && $0.maxLat <= box.maxLat })
	}

	@Test("a rooftop past the search box's edge, from a tile reaching over it, gets no box, so none is inside out")
	func refineBoxesSkipOutside() {
		let box = GeoBounds(minLon: center.longitude - 0.01, minLat: center.latitude - 0.01, maxLon: center.longitude + 0.01, maxLat: center.latitude + 0.01)
		let rooftops = RooftopSites.tallest([
			square(side: 40, height: 200),
			square(side: 40, east: 3_000, height: 250)
		])
		let boxes = RooftopSites.refineBoxes(around: rooftops, within: box)
		#expect(boxes.count == 1)
		#expect(boxes.allSatisfy { $0.minLon <= $0.maxLon && $0.minLat <= $0.maxLat })
	}

	@Test("a roof's area is measured in square meters")
	func roofArea() {
		#expect(abs(RooftopSites.roofArea(square(side: 20, height: 10).outline) - 400) < 4)
		#expect(RooftopSites.roofArea([center]) == 0)
	}

	// MARK: Sky deck

	/// A rooftop on a square `side` meters across, `east` and `north` meters from the center.
	private func rooftop(side: Double, east: Double = 0, north: Double = 0, height: Double) -> RooftopSites.Rooftop {
		let footprint = square(side: side, east: east, north: north, height: height)
		let middle = CLLocationCoordinate2D(
			latitude: footprint.outline.map(\.latitude).reduce(0, +) / 4,
			longitude: footprint.outline.map(\.longitude).reduce(0, +) / 4
		)
		return RooftopSites.Rooftop(coordinate: middle, height: height, outline: footprint.outline)
	}

	/// Meters east and north of `b` from `a`.
	private func offset(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> SIMD2<Double> {
		let metersPerLat = SpatialFrame.metersPerDegreeLatitude
		let metersPerLon = metersPerLat * cos(a.latitude * .pi / 180)
		return SIMD2((b.longitude - a.longitude) * metersPerLon, (b.latitude - a.latitude) * metersPerLat)
	}

	@Test("a sky deck hangs out from the face whose view the other towers block least")
	func deckFacesAwayFromTowers() throws {
		let tower = rooftop(side: 40, height: 250)
		// Tall towers to the north and the east; the west and south are open, the west a little less.
		let others = [tower, rooftop(side: 30, north: 300, height: 220), rooftop(side: 30, east: 300, height: 200), rooftop(side: 30, east: -900, height: 150)]
		let deck = try #require(RooftopSites.deck(on: tower, among: others))
		#expect(abs(deck.facing - 180) < 1, "\(deck.facing)")
		// The seat is over the street, the overhang out from the middle of the south face.
		let seat = offset(tower.coordinate, deck.coordinate)
		#expect(abs(seat.x) < 0.5)
		#expect(abs(seat.y + 20 + RooftopSites.deckOverhang) < 0.5, "\(seat)")
	}

	@Test("with nothing round it, a sky deck hangs off the widest face, and none off a roof with no outline")
	func deckOnWidestFace() throws {
		let metersPerLat = SpatialFrame.metersPerDegreeLatitude
		let metersPerLon = metersPerLat * cos(center.latitude * .pi / 180)
		// 60 m east to west, 20 m north to south: the north and south faces are the wide ones.
		let outline = [(-30.0, -10.0), (30, -10), (30, 10), (-30, 10)].map {
			CLLocationCoordinate2D(latitude: center.latitude + $0.1 / metersPerLat, longitude: center.longitude + $0.0 / metersPerLon)
		}
		let deck = try #require(RooftopSites.deck(on: RooftopSites.Rooftop(coordinate: center, height: 200, outline: outline), among: []))
		#expect(abs(deck.facing) < 1 || abs(deck.facing - 180) < 1, "\(deck.facing)")
		#expect(RooftopSites.deck(on: RooftopSites.Rooftop(coordinate: center, height: 200), among: []) == nil)
	}

	@Test("a tower close enough to be left out of the picker still blocks a sky deck's view")
	func deckScoredAgainstNeighbors() throws {
		let tower = square(side: 40, height: 250)
		let neighbor = square(side: 30, north: 70, height: 230)
		let box = GeoBounds(minLon: center.longitude - 0.01, minLat: center.latitude - 0.01, maxLon: center.longitude + 0.01, maxLat: center.latitude + 0.01)
		let found = try #require(RooftopSites.searchWithNeighbors(in: box, maxTiles: 160) { _, _ in [tower, neighbor] })
		#expect(found.tallest.map(\.height) == [250])
		#expect(found.neighbors.map(\.height) == [250, 230])
		let picked = try #require(found.tallest.first)
		let deck = try #require(RooftopSites.deck(on: picked, among: found.neighbors))
		#expect(abs(deck.facing) > 45 && abs(deck.facing - 360) > 45, "\(deck.facing)")
	}

	@Test("a building under half the tower's height, like its podium, doesn't count against a face")
	func deckIgnoresLowBuildings() throws {
		let tower = rooftop(side: 40, height: 250)
		let podium = rooftop(side: 30, east: 60, height: 100)
		let alone = try #require(RooftopSites.deck(on: tower, among: []))
		let withPodium = try #require(RooftopSites.deck(on: tower, among: [podium]))
		#expect(alone.facing == withPodium.facing)
	}

	@Test("the point behind a sky deck's seat is inside the tower it hangs off")
	func towerBehindDeck() throws {
		let tower = rooftop(side: 40, height: 250)
		let deck = try #require(RooftopSites.deck(on: tower, among: [tower]))
		#expect(!SpatialBuildings.contains(tower.outline, deck.coordinate))
		#expect(SpatialBuildings.contains(tower.outline, RooftopSites.tower(behind: deck.coordinate, facing: deck.facing)))
	}

}
