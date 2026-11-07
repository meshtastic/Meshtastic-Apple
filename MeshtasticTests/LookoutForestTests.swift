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

	@Test("the trees stand in the same places every time, off the summit and inside 2.6 km")
	func spots() {
		let spots = LookoutForest.spots()
		#expect(spots == LookoutForest.spots())
		let kept = spots.filter(\.kept)
		#expect(!kept.isEmpty)
		#expect(kept.allSatisfy { $0.distance >= LookoutForest.nearest && $0.distance <= LookoutForest.farthest })
		#expect(kept.allSatisfy { (0..<360).contains($0.bearing) })
		// Thinned toward the far edge: fewer survive in the last stretch than just inside it.
		let edge = kept.filter { $0.distance > 2_400 }.count
		let inside = kept.filter { $0.distance > 1_500 && $0.distance <= 1_700 }.count
		#expect(edge < inside)
	}

	@Test("every tree fits the triangle budget, and is the painting's size")
	func budgetAndSize() {
		let kept = LookoutForest.spots().filter(\.kept)
		let triangles = kept.reduce(0) { $0 + LookoutForest.triangles(at: $1.distance) }
		// All of them would fit, so on fully forested ground the band reaches 2.6 km.
		#expect(triangles <= LookoutForest.triangleBudget)
		let near = kept.filter { $0.distance < LookoutForest.nearDetail }
		#expect(near.allSatisfy { (0.6...1.5).contains($0.scale) })
		let tallest = LookoutForest.nearCones.map(\.tip).max() ?? 0
		#expect(tallest == 12.5)
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
		let faces = LookoutForest.faces(turn: 0.3, scale: 1, near: true)
		#expect(faces.count == LookoutForest.triangles(at: 100))
		#expect(faces.allSatisfy { $0.normal.y > 0 && abs(simd_length($0.normal) - 1) < 1e-9 })
		let image = try #require(LookoutForest.palette())
		#expect(image.width == LookoutForest.shades && image.height == LookoutForest.lightLevels)
		let dark = LookoutForest.paletteCoordinate(shade: 0, lit: 0)
		let bright = LookoutForest.paletteCoordinate(shade: LookoutForest.shades - 1, lit: 1)
		#expect(dark.x < bright.x && dark.y < bright.y)
	}
}
