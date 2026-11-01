//
//  HillshadeDataZoomTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Hillshade stops past the terrain data")
struct HillshadeDataZoomTests {

	@Test func globalTerrainShadesFullThenFadesThenStops() {
		#expect(HillshadeTileOverlay.strength(zoom: 10, dataMaxZoom: 12) == 1)
		#expect(HillshadeTileOverlay.strength(zoom: 13, dataMaxZoom: 12) == 1)
		#expect(HillshadeTileOverlay.strength(zoom: 14, dataMaxZoom: 12) == 0.5)
		#expect(HillshadeTileOverlay.strength(zoom: 15, dataMaxZoom: 12) == 0)
		#expect(HillshadeTileOverlay.strength(zoom: 18, dataMaxZoom: 12) == 0)
	}

	@Test func regionalTerrainShadesToItsOwnLimit() {
		#expect(HillshadeTileOverlay.strength(zoom: 15, dataMaxZoom: 15) == 1)
		#expect(HillshadeTileOverlay.strength(zoom: 16, dataMaxZoom: 15) == 1)
		#expect(HillshadeTileOverlay.strength(zoom: 17, dataMaxZoom: 15) == 0.5)
	}

	/// An archive holding one-byte placeholder tiles at `tileIDs`; `dataMaxZoom` only asks whether
	/// they exist.
	private func archive(bounds: GeoBounds, minZoom: Int, maxZoom: Int, tileIDs: [UInt64] = []) throws -> URL {
		let entries = tileIDs.sorted().enumerated()
			.map { PMTilesArchive.Entry(tileID: $0.element, offset: UInt64($0.offset), length: 1, runLength: 1) }
		let tiles = tileIDs
		let root = PMTilesExtractor.serializeDirectory(entries)
		let payload = Data(repeating: 0, count: tiles.count)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: UInt64(payload.count),
			numTiles: UInt64(tiles.count), bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, tileType: .webp, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try (header + root + payload).write(to: url)
		return url
	}

	@Test func dataZoomIsTheRegionalArchivesWhereItHasTheTileElseTheGlobalOnes() async throws {
		let region = GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -122.0, maxLat: 47.8)
		// The regional header claims the whole region, but it holds one z13 tile in the west: the
		// rest is like sea, where Mapterhorn has no tiles.
		let west = TerrainStore.tilePixel(latitude: 47.55, longitude: -122.45, z: 13, size: 256)
		let global = try archive(bounds: region, minZoom: 0, maxZoom: 12)
		let regional = try archive(bounds: region, minZoom: 13, maxZoom: 15, tileIDs: [PMTilesArchive.zxyToTileID(z: 13, x: UInt32(west.x), y: UInt32(west.y))])
		defer { [global, regional].forEach { try? FileManager.default.removeItem(at: $0) } }
		let store = TerrainStore()
		await store.configure(sources: [TerrainSource(globalURL: global, regionalURL: regional, bounds: region)])

		// Zoom 13: the tile itself. Zoom 16: a descendant, past the regional data, still its limit.
		#expect(await store.dataMaxZoom(z: 13, x: west.x, y: west.y) == 15)
		#expect(await store.dataMaxZoom(z: 16, x: west.x * 8, y: west.y * 8) == 15)
		let east = TerrainStore.tilePixel(latitude: 47.55, longitude: -122.05, z: 14, size: 256)
		let away = TerrainStore.tilePixel(latitude: 40, longitude: -100, z: 14, size: 256)
		#expect(await store.dataMaxZoom(z: 14, x: east.x, y: east.y) == 12)
		#expect(await store.dataMaxZoom(z: 14, x: away.x, y: away.y) == nil)
	}

	@Test func archiveKnowsWhichTilesItHasWithoutReadingThem() throws {
		let bounds = GeoBounds(minLon: -180, minLat: -85, maxLon: 180, maxLat: 85)
		let url = try archive(bounds: bounds, minZoom: 13, maxZoom: 15, tileIDs: [PMTilesArchive.zxyToTileID(z: 13, x: 1307, y: 2857)])
		defer { try? FileManager.default.removeItem(at: url) }
		let archive = try #require(PMTilesArchive(url: url))
		#expect(archive.hasTile(z: 13, x: 1307, y: 2857))
		#expect(!archive.hasTile(z: 13, x: 1308, y: 2857))
		#expect(!archive.hasTile(z: 12, x: 653, y: 1428))
	}
}
