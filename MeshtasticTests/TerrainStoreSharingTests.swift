//
//  TerrainStoreSharingTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Meshtastic

/// The store decodes and resamples off the actor, for many callers at once: tiles must come out the
/// same as they did one at a time, margins and all.
@Suite("Terrain store sharing")
struct TerrainStoreSharingTests {
	/// The middle of a 3 by 3 block of z10 tiles over Seattle.
	private let center = (x: 164, y: 357)
	private let pixels = 64

	/// Encodes a grid of elevations into a Terrarium-RGB PNG the way Mapterhorn does.
	private func terrariumPNG(size: Int, elevation: (Int, Int) -> Double) throws -> Data {
		var rgba = [UInt8](repeating: 255, count: size * size * 4)
		for y in 0..<size {
			for x in 0..<size {
				let value = elevation(x, y) + 32768
				let base = (y * size + x) * 4
				rgba[base] = UInt8(min(max(value / 256, 0), 255))
				rgba[base + 1] = UInt8(min(max(value.truncatingRemainder(dividingBy: 256), 0), 255))
				rgba[base + 2] = UInt8(min(max((value - value.rounded(.down)) * 256, 0), 255))
			}
		}
		let image: CGImage = try #require(rgba.withUnsafeMutableBytes { buffer in
			CGContext(
				data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
			)?.makeImage()
		})
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
		CGImageDestinationAddImage(destination, image, nil)
		#expect(CGImageDestinationFinalize(destination))
		return data as Data
	}

	/// A terrain archive of the 3 by 3 block around `center` (less any past the world's edge), the
	/// ground rising one meter per pixel eastward across all of it, and a source for it.
	private func rampSource(center: (x: Int, y: Int) = (164, 357)) throws -> TerrainSource {
		var tiles: [(id: UInt64, data: Data)] = []
		for dy in -1...1 {
			for dx in -1...1 where center.x + dx >= 0 {
				let column = (dx + 1) * pixels
				let data = try terrariumPNG(size: pixels) { x, _ in Double(100 + column + x) }
				tiles.append((PMTilesArchive.zxyToTileID(z: 10, x: UInt32(center.x + dx), y: UInt32(center.y + dy)), data))
			}
		}
		tiles.sort { $0.id < $1.id }
		var offset: UInt64 = 0
		let entries = tiles.map { tile in
			defer { offset += UInt64(tile.data.count) }
			return PMTilesArchive.Entry(tileID: tile.id, offset: offset, length: UInt32(tile.data.count), runLength: 1)
		}
		let payload = tiles.reduce(Data()) { $0 + $1.data }
		let northWest = GeoBounds.tile(z: 10, x: max(center.x - 1, 0), y: center.y - 1)
		let southEast = GeoBounds.tile(z: 10, x: center.x + 1, y: center.y + 1)
		let bounds = GeoBounds(minLon: northWest.minLon, minLat: southEast.minLat, maxLon: southEast.maxLon, maxLat: northWest.maxLat)
		let root = PMTilesExtractor.serializeDirectory(entries)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: UInt64(payload.count),
			numTiles: UInt64(tiles.count), bounds: bounds, minZoom: 10, maxZoom: 10,
			tileType: .webp, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("ramp-\(UUID().uuidString).pmtiles")
		try (header + root + payload).write(to: url)
		return TerrainSource(globalURL: url, regionalURLs: [], bounds: bounds)
	}

	@Test func theMarginIsReadFromTheNeighbors() async throws {
		let store = TerrainStore()
		await store.configure(sources: [try rampSource()])
		let tile = try #require(await store.elevationTile(z: 10, x: center.x, y: center.y, margin: 1))
		let row = Array(tile.elevations[(tile.gridSize * 5)..<(tile.gridSize * 6)])
		// Clamped to the tile's own edge, the first and last two would be equal.
		#expect(zip(row, row.dropFirst()).allSatisfy { $0 < $1 }, "the ground keeps rising into both neighbors")
	}

	@Test func theMarginStopsAtTheWorldsEdge() async throws {
		let store = TerrainStore()
		await store.configure(sources: [try rampSource(center: (0, 357))])
		let tile = try #require(await store.elevationTile(z: 10, x: 0, y: 357, margin: 1))
		let row = Array(tile.elevations[(tile.gridSize * 5)..<(tile.gridSize * 6)])
		// West of x = 0 there's nothing: the margin takes the tile's own west edge, not its east one.
		#expect(abs(row[0] - row[1]) < 0.5)
		#expect(row[0] < row[row.count - 1])
	}

	@Test func manyTasksGetTheSameTilesAsOne() async throws {
		let source = try rampSource()
		// Every z12 tile inside the middle z10 one, past its data zoom, so each is sampled from it.
		let keys = (0..<4).flatMap { dy in (0..<4).map { dx in (x: center.x * 4 + dx, y: center.y * 4 + dy) } }

		let alone = TerrainStore()
		await alone.configure(sources: [source])
		var expected: [[Float]] = []
		for key in keys {
			expected.append(try #require(await alone.elevationTile(z: 12, x: key.x, y: key.y, margin: 2)).elevations)
		}

		let shared = TerrainStore()
		await shared.configure(sources: [source])
		// Each tile asked for three times at once.
		let results = await withTaskGroup(of: (Int, [Float]?).self) { group in
			for (index, key) in keys.enumerated() {
				for _ in 0..<3 {
					group.addTask { (index, await shared.elevationTile(z: 12, x: key.x, y: key.y, margin: 2)?.elevations) }
				}
			}
			var results: [(Int, [Float]?)] = []
			for await result in group { results.append(result) }
			return results
		}
		#expect(results.count == keys.count * 3)
		for (index, elevations) in results {
			#expect(elevations == expected[index])
		}
	}
}
