//
//  OfflineRegionalTerrainTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Regional terrain from every z6 archive")
struct OfflineRegionalTerrainTests {

	/// Seattle across to Idaho: z6 tiles 10/22 and 11/22.
	private let bounds = GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -116.0, maxLat: 47.8)

	private func url(x: UInt32, y: UInt32) -> URL {
		OfflineMapManager.regionalTerrainArchive(tileX: x, tileY: y)!
	}

	/// The z13 tile holding a point.
	private func z13(lat: Double, lon: Double) -> (x: UInt32, y: UInt32) {
		PMTilesExtractor.tileXY(lon: lon, lat: lat, z: 13)
	}

	/// A regional archive for one z6 tile holding `payload` at a z13 tile, the header bounds the z6
	/// tile's own, like Mapterhorn's.
	private func regionalArchive(z6 x: UInt32, _ y: UInt32, tile: (x: UInt32, y: UInt32), payload: Data) -> Data {
		let entries = [PMTilesArchive.Entry(tileID: PMTilesArchive.zxyToTileID(z: 13, x: tile.x, y: tile.y), offset: 0, length: UInt32(payload.count), runLength: 1)]
		let root = PMTilesExtractor.serializeDirectory(entries)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: UInt64(payload.count),
			numTiles: 1, bounds: GeoBounds.tile(z: 6, x: Int(x), y: Int(y)), minZoom: 13, maxZoom: 15,
			tileType: .webp, tileCompression: .none
		)
		return header + root + payload
	}

	/// Serves archives from memory over the extractor's range seam; anything else is a 404.
	private func extractor(_ archives: [URL: Data]) -> PMTilesExtractor {
		PMTilesExtractor { url, range, _ in
			guard let data = archives[url] else { return .init(statusCode: 404, body: Data()) }
			let start = Int(range.lowerBound)
			guard start < data.count else { return .init(statusCode: 416, body: Data()) }
			let end = min(Int(range.upperBound), data.count - 1)
			return .init(statusCode: 206, headers: ["Content-Range": "bytes \(start)-\(end)/\(data.count)", "ETag": "\"\(url.lastPathComponent)\""],
						 body: data.subdata(in: start..<(end + 1)))
		}
	}

	private func scratchDirectory() throws -> URL {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	@Test func eachArchiveTheRegionReachesIsExtractedAndAMissingOneSkipped() async throws {
		let seattle = z13(lat: 47.55, lon: -122.3)
		let extractor = extractor([url(x: 10, y: 22): regionalArchive(z6: 10, 22, tile: seattle, payload: Data(repeating: 1, count: 100))])
		let dir = try scratchDirectory()
		defer { try? FileManager.default.removeItem(at: dir) }

		let extracts = try await OfflineMapManager.extractRegionalTerrain(
			extractor: extractor, bounds: bounds, directory: dir, basemapFileName: "map.pmtiles", budget: .max
		)
		#expect(extracts.map(\.record) == [OfflineMapRegionalTerrain(fileName: "map-terrain-hi-6-10-22.pmtiles", tileX: 10, tileY: 22, etag: "\"6-10-22.pmtiles\"")])
		let written = try #require(PMTilesArchive(url: dir.appendingPathComponent("map-terrain-hi-6-10-22.pmtiles")))
		#expect(written.tileData(z: 13, x: seattle.x, y: seattle.y) == Data(repeating: 1, count: 100))
	}

	@Test func theBudgetCountsEverythingExtractedTogether() async throws {
		let extractor = extractor([
			url(x: 10, y: 22): regionalArchive(z6: 10, 22, tile: z13(lat: 47.55, lon: -122.3), payload: Data(repeating: 1, count: 100)),
			url(x: 11, y: 22): regionalArchive(z6: 11, 22, tile: z13(lat: 47.55, lon: -117.4), payload: Data(repeating: 2, count: 100))
		])
		let dir = try scratchDirectory()
		defer { try? FileManager.default.removeItem(at: dir) }

		let extracts = try await OfflineMapManager.extractRegionalTerrain(
			extractor: extractor, bounds: bounds, directory: dir, basemapFileName: "map.pmtiles", budget: 150
		)
		#expect(extracts.map(\.record.fileName) == ["map-terrain-hi-6-10-22.pmtiles"])
		#expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("map-terrain-hi-6-11-22.pmtiles").path))
	}

	@Test func theStoreReadsEachTileFromTheArchiveThatHasIt() async throws {
		let seattle = z13(lat: 47.55, lon: -122.3)
		let spokane = z13(lat: 47.55, lon: -117.4)
		let dir = try scratchDirectory()
		defer { try? FileManager.default.removeItem(at: dir) }
		let west = dir.appendingPathComponent("west.pmtiles")
		let east = dir.appendingPathComponent("east.pmtiles")
		try regionalArchive(z6: 10, 22, tile: seattle, payload: Data("west".utf8)).write(to: west)
		try regionalArchive(z6: 11, 22, tile: spokane, payload: Data("east".utf8)).write(to: east)
		// A global archive with no tiles: only its zoom range matters here.
		let global = dir.appendingPathComponent("global.pmtiles")
		let root = PMTilesExtractor.serializeDirectory([])
		try (PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count), metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: 0, numTiles: 0, bounds: bounds, minZoom: 0, maxZoom: 12,
			tileType: .webp, tileCompression: .none
		) + root).write(to: global)

		let store = TerrainStore()
		await store.configure(sources: [TerrainSource(globalURL: global, regionalURLs: [west, east], bounds: bounds)])
		guard case .data(let fromWest) = await store.coverageTile(z: 13, x: Int(seattle.x), y: Int(seattle.y)),
			  case .data(let fromEast) = await store.coverageTile(z: 13, x: Int(spokane.x), y: Int(spokane.y)) else {
			Issue.record("expected both regional tiles")
			return
		}
		#expect(fromWest == Data("west".utf8))
		#expect(fromEast == Data("east".utf8))
		// Inside the region but in neither archive: only global data, which stops at 12.
		let between = z13(lat: 47.55, lon: -119.0)
		#expect(await store.dataMaxZoom(z: 13, x: Int(between.x), y: Int(between.y)) == 12)
		#expect(await store.dataMaxZoom(z: 14, x: Int(seattle.x) * 2, y: Int(seattle.y) * 2) == 15)
	}

	@Test func recordsRoundTripAndOlderManifestsStillReadTheirOneExtract() throws {
		let terrain = OfflineMapTerrain(
			fileName: "map-terrain.pmtiles", regionalFileName: "map-terrain-hi-6-10-22.pmtiles", byteCount: 1,
			downloadedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), maxZoom: 15,
			regionalArchives: [
				OfflineMapRegionalTerrain(fileName: "map-terrain-hi-6-10-22.pmtiles", tileX: 10, tileY: 22, etag: "\"a\""),
				OfflineMapRegionalTerrain(fileName: "map-terrain-hi-6-11-22.pmtiles", tileX: 11, tileY: 22, etag: "\"b\"")
			]
		)
		let decoded = try JSONDecoder().decode(OfflineMapTerrain.self, from: JSONEncoder().encode(terrain))
		#expect(decoded == terrain)
		#expect(decoded.regionalFiles.count == 2)

		let older = """
		{ "fileName": "old-terrain.pmtiles", "regionalFileName": "old-terrain-hi.pmtiles", "regionalETag": "\\"r\\"",
		  "byteCount": 10, "downloadedAt": 700000000, "maxZoom": 15 }
		"""
		let legacy = try JSONDecoder().decode(OfflineMapTerrain.self, from: Data(older.utf8))
		#expect(legacy.regionalFiles == [OfflineMapRegionalTerrain(fileName: "old-terrain-hi.pmtiles", etag: "\"r\"")])
	}

	@Test func removingSweepsEveryRegionalFileForTheBasemap() throws {
		let dir = try scratchDirectory()
		defer { try? FileManager.default.removeItem(at: dir) }
		let names = ["map-terrain-hi.pmtiles", "map-terrain-hi-6-10-22.pmtiles", "map-terrain-hi-6-11-22.pmtiles", "map-terrain.pmtiles", "other-terrain-hi-6-10-22.pmtiles"]
		for name in names { try Data("x".utf8).write(to: dir.appendingPathComponent(name)) }
		OfflineMapManager.removeRegionalTerrainFiles(forBasemap: "map.pmtiles", in: dir)
		let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
		#expect(left == ["map-terrain.pmtiles", "other-terrain-hi-6-10-22.pmtiles"])
	}
}
