//
//  LookoutForestTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/7/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Fire lookout forest")
struct LookoutForestTests {

	private func spots(to farthest: Double) -> [LookoutForest.Spot] {
		var result: [LookoutForest.Spot] = []
		LookoutForest.forEachSpot(farthest: farthest) { result.append($0); return true }
		return result
	}

	@Test("the spots are the same every time, off the summit, nearest first, and far trees stand larger")
	func spotsAreStable() {
		let spots = spots(to: 6_000)
		#expect(spots == self.spots(to: 6_000))
		#expect(spots.allSatisfy { $0.distance >= LookoutForest.nearest * 0.9 })
		#expect(spots.allSatisfy { (0..<360).contains($0.bearing) })
		#expect((spots.first?.distance ?? 0) < (spots.last?.distance ?? 0))
		// Near trees keep the painting's sizes. Far stands are wider, and taller more slowly.
		#expect(spots.filter { $0.distance < LookoutForest.paintedReach }.allSatisfy { (0.6...1.5).contains($0.width) && $0.width == $0.height })
		#expect(spots.filter { $0.distance > 5_900 }.allSatisfy { $0.width > 1.4 && $0.height < $0.width })
	}

	@Test("the band starts at the first forest above the sill, skipping ground under it and ground behind a ridge")
	func bandStartsAtFirstVisibleForest() {
		let spokes = 4
		// Rings out from the summit: steep slopes under the sill, then a valley floor in view.
		let distances: [Double] = [100, 500, 1_000, 3_000, 6_000, 9_000]
		let profile: [Float] = [1_950, 1_500, 1_100, 1_100, 1_300, 1_500]
		let elevations = profile.flatMap { Array(repeating: $0, count: spokes + 1) }
		let view = LookoutForest.view(distances: distances, elevations: elevations, spokes: spokes, eye: 2_000) { _ in true }
		// 3 km: 900 m below at 3 km is 16.7° down, under the sill. 6 km: 700 m below is 6.7°, still
		// under it. 9 km: 500 m below is about 3.2°, above the sill.
		#expect(view.bands[0] == LookoutForest.Band(start: 9_000, end: 9_000 * LookoutForest.bandDepth))
		// No forest anywhere: no band.
		let bare = LookoutForest.view(distances: distances, elevations: elevations, spokes: spokes, eye: 2_000) { _ in false }
		#expect(bare.bands.allSatisfy { $0 == nil })
	}

	@Test("ground behind a nearer ridge is hidden")
	func horizon() {
		let spokes = 1
		let distances: [Double] = [200, 2_000, 4_000]
		// A ridge at 2 km as high as the eye, then lower ground behind it.
		let elevations: [Float] = [1_000, 1_000, 2_000, 2_000, 1_900, 1_900]
		let view = LookoutForest.view(distances: distances, elevations: elevations, spokes: spokes, eye: 2_000) { _ in true }
		#expect(view.bands[0]?.start == 2_000)
		// At 4 km the ridge stands higher in the view than the ground there.
		let behind = (1_900.0 - 2_000 - 4_000 * 4_000 / (2 * 7_450_000.0)) / 4_000
		#expect(view.horizon[2 * (spokes + 1)] > behind)
	}

	@Test("the painting's tree, and the triangle cost by detail")
	func sizeAndCost() {
		#expect(LookoutForest.nearCones.map(\.tip).max() == 12.5)
		#expect(LookoutForest.triangles(at: 100) == LookoutForest.nearCones.count * LookoutForest.nearSides)
		#expect(LookoutForest.triangles(at: 5_000) == LookoutForest.farCones.count * LookoutForest.farSides)
	}

	@Test("trees grow on forest, or with no land cover, on the ground painted forest, never near the snow line")
	func forestTest() {
		#expect(LookoutForest.isForest(cover: .forest, elevation: 400, latitude: 47.5, heightFraction: 0.9))
		#expect(!LookoutForest.isForest(cover: .grass, elevation: 400, latitude: 47.5, heightFraction: 0.1))
		#expect(!LookoutForest.isForest(cover: .water, elevation: 0, latitude: 47.5, heightFraction: 0))
		#expect(!LookoutForest.isForest(cover: .urban, elevation: 50, latitude: 47.5, heightFraction: 0.1))
		#expect(LookoutForest.isForest(cover: nil, elevation: 400, latitude: 47.5, heightFraction: 0.3))
		#expect(!LookoutForest.isForest(cover: nil, elevation: 400, latitude: 47.5, heightFraction: 0.7))
		#expect(!LookoutForest.isForest(cover: nil, elevation: 0.2, latitude: 47.5, heightFraction: 0.1))
		// The snow line at 47.5° is about 2,050 m.
		#expect(!LookoutForest.isForest(cover: .forest, elevation: 1_900, latitude: 47.5, heightFraction: 0.5))
	}

	@Test("a tree stands on the terrain as it's drawn, between the heights at the cell's corners")
	func groundElevation() throws {
		let spokes = 4
		let distances = [100.0, 200.0, 400.0]
		// Rows are rings, columns spokes plus the repeat of the first.
		let elevations: [Float] = [10, 20, 30, 40, 10,
								   50, 60, 70, 80, 50,
								   90, 100, 110, 120, 90]
		let middle = try #require(LookoutForest.groundElevation(bearing: 45, distance: 150, distances: distances, elevations: elevations, spokes: spokes))
		#expect(abs(middle - 35) < 0.001)
		let corner = try #require(LookoutForest.groundElevation(bearing: 0, distance: 200, distances: distances, elevations: elevations, spokes: spokes))
		#expect(abs(corner - 50) < 0.001)
		#expect(LookoutForest.groundElevation(bearing: 0, distance: 500, distances: distances, elevations: elevations, spokes: spokes) == nil)
	}

	@Test("the cones are faceted, upright, and lit from the palette")
	func shapeAndPalette() throws {
		let faces = LookoutForest.faces(turn: 0.3, width: 1, height: 1, near: true)
		#expect(faces.count == LookoutForest.triangles(at: 100))
		#expect(faces.allSatisfy { $0.normal.y > 0 && abs(simd_length($0.normal) - 1) < 1e-9 })
		let image = try #require(LookoutForest.palette())
		#expect(image.width == LookoutForest.shades * LookoutForest.hazeLevels && image.height == LookoutForest.lightLevels)
		let dark = LookoutForest.paletteCoordinate(shade: 0, lit: 0, distance: 1_000)
		let bright = LookoutForest.paletteCoordinate(shade: LookoutForest.shades - 1, lit: 1, distance: 1_000)
		#expect(dark.x < bright.x && dark.y < bright.y)
		// Farther trees read from hazier columns.
		let far = LookoutForest.paletteCoordinate(shade: 0, lit: 0, distance: 30_000)
		#expect(far.x > bright.x)
	}

	@Test("a band thins in at its near edge and out at its far edge")
	func bandEdges() {
		let band = LookoutForest.Band(start: 4_000, end: 6_400)
		#expect(band.density(at: 4_000) == 0)
		#expect(band.density(at: 5_000) > 0.9)
		#expect(band.density(at: 6_400) == 0)
	}
}
