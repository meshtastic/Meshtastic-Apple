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

	@Test("the near spots are the same every time, off the summit, nearest first, at true size")
	func spotsAreStable() {
		let spots = spots(to: 1_500)
		#expect(spots == self.spots(to: 1_500))
		#expect(spots.allSatisfy { $0.distance >= LookoutForest.nearest * 0.9 })
		#expect(spots.allSatisfy { (0..<360).contains($0.bearing) })
		#expect((spots.first?.distance ?? 0) < (spots.last?.distance ?? 0))
		// Every tree is the painting's size.
		#expect(spots.allSatisfy { (0.6...1.5).contains($0.width) && $0.width == $0.height })
	}

	@Test("ground under the sill, or behind a nearer ridge, is hidden")
	func visibility() {
		let spokes = 1
		let eye = 2_000.0
		// Steep slopes under the sill: 900 m below at 3 km is about 17° down.
		#expect(!LookoutForest.shows(top: 1_100, distance: 3_000, eye: eye, horizon: -.infinity))
		// 500 m below at 9 km is about 3.2° down, above the sill.
		#expect(LookoutForest.shows(top: 1_500, distance: 9_000, eye: eye, horizon: -.infinity))
		// A ridge at 2 km as high as the eye hides lower ground behind it.
		let distances: [Double] = [200, 2_000, 4_000]
		let elevations: [Float] = [1_000, 1_000, 2_000, 2_000, 1_900, 1_900]
		let horizon = LookoutForest.horizon(distances: distances, elevations: elevations, spokes: spokes, eye: eye)
		#expect(!LookoutForest.shows(top: 1_920, distance: 4_000, eye: eye, horizon: horizon[2 * (spokes + 1)]))
		#expect(LookoutForest.shows(top: 2_100, distance: 4_000, eye: eye, horizon: horizon[2 * (spokes + 1)]))
	}

	@Test("trees thin out toward the reach, with no hard edge")
	func density() {
		#expect(LookoutForest.density(at: 5_000) == 1)
		#expect(LookoutForest.density(at: 12_500) > 0 && LookoutForest.density(at: 12_500) < 1)
		#expect(LookoutForest.density(at: LookoutForest.reach) == 0)
	}

	@Test("the front band starts big and shrinks to a row's size, the same every time")
	func frontBand() {
		let front = 6_000.0
		#expect(abs(LookoutForest.frontScale(at: front, from: front) - LookoutForest.frontBoost * LookoutForest.rowScale(at: front)) < 1e-9)
		let back = front * LookoutForest.frontDepth
		#expect(abs(LookoutForest.frontScale(at: back, from: front) - LookoutForest.rowScale(at: back)) < 1e-9)
		var spots: [LookoutForest.Spot] = []
		LookoutForest.forEachFrontSpot(spoke: 40, spokes: 720, from: front) { spots.append($0); return true }
		var again: [LookoutForest.Spot] = []
		LookoutForest.forEachFrontSpot(spoke: 40, spokes: 720, from: front) { again.append($0); return true }
		#expect(spots == again && !spots.isEmpty)
		#expect(spots.allSatisfy { $0.bearing >= 20 && $0.bearing <= 20.5 })
		#expect(spots.allSatisfy { $0.distance > front * 0.95 && $0.distance < back * 1.05 })
	}

	@Test("rows come nearest first, one per spoke at each step, the same every time")
	func rows() {
		var rows: [LookoutForest.Row] = []
		LookoutForest.forEachRow(farthest: 2_000, spokes: 8) { rows.append($0); return true }
		var again: [LookoutForest.Row] = []
		LookoutForest.forEachRow(farthest: 2_000, spokes: 8) { again.append($0); return true }
		#expect(rows == again)
		#expect(rows.count.isMultiple(of: 8) && !rows.isEmpty)
		#expect((rows.first?.distance ?? 0) < (rows.last?.distance ?? 0))
		#expect(rows.allSatisfy { $0.distance > LookoutForest.rowsFrom * 0.99 })
	}

	@Test("a row reads its own stretch of trees from the band for its haze and the sun's side")
	func rowCoordinates() throws {
		let near = LookoutForest.rowCoordinates(offset: 0.5, width: 20, distance: 2_000, sunOnRight: false)
		let lit = LookoutForest.rowCoordinates(offset: 0.5, width: 20, distance: 2_000, sunOnRight: true)
		let far = LookoutForest.rowCoordinates(offset: 0.5, width: 20, distance: 14_000, sunOnRight: false)
		#expect(abs(Double(near.u1 - near.u0) - 20 / LookoutForest.rowTextureMeters) < 1e-6)
		#expect(near.u0 >= 0 && near.u1 <= 1)
		#expect(lit.v0 > near.v0 && far.v0 > lit.v0)
		#expect(near.v1 < lit.v0)
		let image = try #require(LookoutForest.rowTexture(width: 256, bandHeight: 32))
		#expect(image.height == 32 * LookoutForest.rowBands)
	}

	@Test("the painting's tree, and the triangle cost by detail")
	func sizeAndCost() {
		#expect(LookoutForest.nearCones.map(\.tip).max() == 12.5)
		#expect(LookoutForest.triangles(at: 100) == LookoutForest.nearCones.count * LookoutForest.nearSides)
		#expect(LookoutForest.triangles(at: 1_000) == LookoutForest.farCones.count * LookoutForest.farSides)
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
}
