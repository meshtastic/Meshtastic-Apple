// PMTilesExtractorTests.swift
// MeshtasticTests
//
// Validates the PMTiles v3 writer against the existing reader (PMTilesArchive)
// and the tile-enumeration math — no network required.

import Testing
import Foundation
@testable import Meshtastic

@Suite("PMTilesExtractor tile math")
struct PMTilesExtractorTileMathTests {

	@Test func tileXY_atZoomZero_isOrigin() {
		#expect(PMTilesExtractor.tileXY(lon: -122.2, lat: 47.6, z: 0) == (0, 0))
		#expect(PMTilesExtractor.tileXY(lon: 150, lat: -40, z: 0) == (0, 0))
	}

	@Test func tileXY_atZoomOne_quadrants() {
		// Pacific NW → north-west quadrant.
		#expect(PMTilesExtractor.tileXY(lon: -122.2, lat: 47.6, z: 1) == (0, 0))
		// East of prime meridian, southern hemisphere → south-east quadrant.
		#expect(PMTilesExtractor.tileXY(lon: 10, lat: -20, z: 1) == (1, 1))
	}

	@Test func tileXY_clampsExtremeLatitude() {
		let (_, y) = PMTilesExtractor.tileXY(lon: 0, lat: 89, z: 4)
		#expect(y == 0) // clamped to the Web-Mercator limit, top row
	}

	@Test func roughByteEstimate_weightsHighZoomTilesLighter() {
		let bounds = GeoBounds(minLon: -122.5, minLat: 47.4, maxLon: -122.2, maxLat: 47.8)
		let standard = PMTilesExtractor.roughByteEstimate(in: bounds, minZoom: 0, maxZoom: 13)
		let high = PMTilesExtractor.roughByteEstimate(in: bounds, minZoom: 0, maxZoom: 15)
		#expect(high > standard)
		// z14/z15 tiles average far smaller than mid-zoom tiles; the high-detail
		// increment must reflect that rather than a flat per-tile constant.
		let addedTiles = PMTilesExtractor.tileCount(in: bounds, minZoom: 14, maxZoom: 15)
		let flatIncrement = Int64(addedTiles) * 34_816
		#expect(high - standard < flatIncrement)
	}

	@Test func tileCount_matchesEnumeratedIDs() {
		let bounds = GeoBounds(minLon: -122.3, minLat: 47.4, maxLon: -122.0, maxLat: 47.7)
		let count = PMTilesExtractor.tileCount(in: bounds, minZoom: 0, maxZoom: 12)
		let ids = PMTilesExtractor.tileIDs(in: bounds, minZoom: 0, maxZoom: 12)
		#expect(count == ids.count)
		#expect(count > 0)
	}

	@Test func tileIDs_areUniquePerZoom() {
		let bounds = GeoBounds(minLon: -1, minLat: -1, maxLon: 1, maxLat: 1)
		let ids = PMTilesExtractor.tileIDs(in: bounds, minZoom: 0, maxZoom: 8)
		#expect(Set(ids).count == ids.count)
	}
}

@Suite("PMTiles directory round-trip")
struct PMTilesDirectoryRoundTripTests {

	@Test func deserializeDirectory_rejectsZeroFirstOffset() {
		// count=1, then tileID/runLength/length/offset values of 0. The first
		// offset is invalid in PMTiles (zero is only a continuation marker).
		#expect(PMTilesArchive.deserializeDirectory(Data([1, 0, 0, 0, 0])).isEmpty)
	}

	@Test func serializeDeserialize_preservesEntries() {
		let entries: [PMTilesArchive.Entry] = [
			.init(tileID: 5, offset: 0, length: 100, runLength: 1),
			.init(tileID: 9, offset: 100, length: 250, runLength: 1),
			.init(tileID: 42, offset: 350, length: 17, runLength: 1)
		].sorted { $0.tileID < $1.tileID }

		let data = PMTilesExtractor.serializeDirectory(entries)
		let decoded = PMTilesArchive.deserializeDirectory(data)

		#expect(decoded.count == entries.count)
		for (a, b) in zip(entries, decoded) {
			#expect(a.tileID == b.tileID)
			#expect(a.offset == b.offset)
			#expect(a.length == b.length)
			#expect(a.runLength == b.runLength)
		}
	}
}

@Suite("PMTiles header round-trip")
struct PMTilesHeaderRoundTripTests {

	@Test func parseHeader_rejectsTruncatedVersionedHeader() {
		var truncated = Data("PMTiles".utf8)
		truncated.append(3)
		#expect(PMTilesArchive.parseHeader(truncated) == nil)
	}

	@Test func buildParse_preservesFields() throws {
		let bounds = GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -121.9, maxLat: 47.8)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: 64,
			metadataOffset: 191, metadataLength: 32,
			tileDataOffset: 223, tileDataLength: 4096,
			numTiles: 12, bounds: bounds, minZoom: 0, maxZoom: 14,
			tileType: .mvt, tileCompression: .gzip
		)
		let parsed = try #require(PMTilesArchive.parseHeader(header))

		#expect(parsed.rootDirOffset == 127)
		#expect(parsed.rootDirLength == 64)
		#expect(parsed.tileDataOffset == 223)
		#expect(parsed.minZoom == 0)
		#expect(parsed.maxZoom == 14)
		#expect(parsed.tileType == .mvt)
		#expect(parsed.tileCompression == .gzip)
		#expect(parsed.internalCompression == .none)
		#expect(abs(parsed.bounds.minLon - bounds.minLon) < 1e-6)
		#expect(abs(parsed.bounds.maxLat - bounds.maxLat) < 1e-6)
	}
}

@Suite("PMTiles full file round-trip")
struct PMTilesFullFileRoundTripTests {

	@Test func archiveWithOutOfRangeDirectoryOffsetDoesNotReadTile() throws {
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: .max, rootDirLength: 1,
			metadataOffset: 127, metadataLength: 0,
			tileDataOffset: 127, tileDataLength: 0,
			numTiles: 0,
			bounds: GeoBounds(minLon: -1, minLat: -1, maxLon: 1, maxLat: 1),
			minZoom: 0, maxZoom: 0, tileType: .png, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try header.write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let archive = try #require(PMTilesArchive(url: url))
		#expect(archive.tileData(z: 0, x: 0, y: 0) == nil)
	}

	@Test func archiveWithOverflowingTileDataOffsetDoesNotReadTile() throws {
		let directory = PMTilesExtractor.serializeDirectory([
			.init(tileID: 0, offset: 1, length: 1, runLength: 1)
		])
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(directory.count),
			metadataOffset: 127 + UInt64(directory.count), metadataLength: 0,
			tileDataOffset: .max, tileDataLength: 0,
			numTiles: 1,
			bounds: GeoBounds(minLon: -1, minLat: -1, maxLon: 1, maxLat: 1),
			minZoom: 0, maxZoom: 0, tileType: .png, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try (header + directory).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let archive = try #require(PMTilesArchive(url: url))
		#expect(archive.tileData(z: 0, x: 0, y: 0) == nil)
	}

	@Test func writtenArchive_readsBackTiles() throws {
		// Build a small archive the way PMTilesExtractor.extract does, with uncompressed
		// payloads, then open it with PMTilesArchive and read every tile back.
		struct Tile { let z: UInt8; let x: UInt32; let y: UInt32; let payload: Data }
		let tiles: [Tile] = [
			.init(z: 10, x: 163, y: 357, payload: Data("tile-a".utf8)),
			.init(z: 12, x: 654, y: 1431, payload: Data("payload-b-longer".utf8)),
			.init(z: 14, x: 2620, y: 5725, payload: Data("c".utf8))
		]

		var tileData = Data()
		var entries: [PMTilesArchive.Entry] = []
		for tile in tiles {
			let id = PMTilesArchive.zxyToTileID(z: tile.z, x: tile.x, y: tile.y)
			entries.append(.init(tileID: id, offset: UInt64(tileData.count), length: UInt32(tile.payload.count), runLength: 1))
			tileData.append(tile.payload)
		}
		entries.sort { $0.tileID < $1.tileID }

		let root = PMTilesExtractor.serializeDirectory(entries)
		let metadata = PMTilesExtractor.metadataJSON()
		let tileDataOffset = UInt64(127 + root.count + metadata.count)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: UInt64(metadata.count),
			tileDataOffset: tileDataOffset, tileDataLength: UInt64(tileData.count),
			numTiles: UInt64(entries.count),
			bounds: GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -121.9, maxLat: 47.8),
			minZoom: 10, maxZoom: 14, tileType: .png, tileCompression: .none
		)

		var file = Data()
		file.append(header)
		file.append(root)
		file.append(metadata)
		file.append(tileData)

		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try file.write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let archive = try #require(PMTilesArchive(url: url))
		for tile in tiles {
			let read = archive.tileData(z: tile.z, x: tile.x, y: tile.y)
			#expect(read == tile.payload)
		}
		// A tile that was never written must not resolve.
		#expect(archive.tileData(z: 14, x: 0, y: 0) == nil)
	}
}
