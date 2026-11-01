//
//  TerrainOcclusionTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Hillshade sky occlusion")
struct TerrainOcclusionTests {

	private let size = 64
	private let margin = 16

	/// A tile whose ground is `height(gx, gy)` over the whole grid, margin included, in grid
	/// coordinates (the tile's own samples start at `margin`).
	private func tile(_ height: (Int, Int) -> Float) -> ElevationTile {
		let grid = size + 2 * margin
		var elevations = [Float](repeating: 0, count: grid * grid)
		for gy in 0..<grid {
			for gx in 0..<grid { elevations[gy * grid + gx] = height(gx, gy) }
		}
		return ElevationTile(z: 12, x: 0, y: 0, size: size, margin: margin, elevations: elevations)
	}

	@Test func flatGroundSeesTheWholeSky() {
		let result = TerrainOcclusion.compute(tile: tile { _, _ in 300 }, metersPerSample: 25, radius: margin)
		#expect(result.allSatisfy { $0 == 0 })
	}

	@Test func aValleyFloorSeesLessSkyThanItsRimAndASummitSeesItAll() {
		let center = Float(margin + size / 2)
		func distance(_ gx: Int, _ gy: Int) -> Float { ((Float(gx) - center) * (Float(gx) - center) + (Float(gy) - center) * (Float(gy) - center)).squareRoot() }
		let bowl = TerrainOcclusion.compute(tile: tile { distance($0, $1) * 20 }, metersPerSample: 25, radius: margin)
		let floor = Int(bowl[(size / 2) * size + size / 2])
		let rim = Int(bowl[(size / 2) * size + size - 1])
		#expect(floor > 100)
		#expect(floor > rim)
		let peak = TerrainOcclusion.compute(tile: tile { 2_000 - distance($0, $1) * 20 }, metersPerSample: 25, radius: margin)
		#expect(peak[(size / 2) * size + size / 2] == 0)
	}

	@Test func aRidgeJustPastTheTileEdgeShadesTheEdge() {
		// A ridge in the margin above the tile only: a tile that read its own samples alone
		// wouldn't see it, and the edge would light up against the next tile's shading.
		let ridge = TerrainOcclusion.compute(tile: tile { _, gy in gy < self.margin - 2 ? 400 : 0 }, metersPerSample: 25, radius: margin)
		#expect(ridge[size / 2] > 60)                        // the tile's top row: 3 of 8 looks see it
		#expect(ridge[(size - 1) * size + size / 2] == 0)    // far below, out of reach
	}

	@Test func theLookReachesAKilometerWithinTheMarginCap() {
		#expect(TerrainOcclusion.radiusSamples(metersPerSample: 100) == 10)
		#expect(TerrainOcclusion.radiusSamples(metersPerSample: 26) == TerrainOcclusion.maxRadiusSamples)
		#expect(TerrainOcclusion.radiusSamples(metersPerSample: 6.5) == TerrainOcclusion.maxRadiusSamples)
		#expect(TerrainOcclusion.steps(radius: 32) == [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 18, 22, 27, 32])
		#expect(TerrainOcclusion.steps(radius: 9).last == 9)
	}
}
