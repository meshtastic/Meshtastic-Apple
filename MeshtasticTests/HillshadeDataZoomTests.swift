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

	/// An archive with no tiles, just a header: all `dataMaxZoom` reads.
	private func emptyArchive(bounds: GeoBounds, minZoom: Int, maxZoom: Int) throws -> URL {
		let root = PMTilesExtractor.serializeDirectory([])
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: 0,
			tileDataOffset: UInt64(127 + root.count), tileDataLength: 0,
			numTiles: 0, bounds: bounds, minZoom: minZoom, maxZoom: maxZoom, tileType: .webp, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try (header + root).write(to: url)
		return url
	}

	@Test func dataZoomIsTheRegionalArchivesWhereItReachesElseTheGlobalOnes() async throws {
		let region = GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -122.0, maxLat: 47.8)
		// High-resolution data only for the western half.
		let regionalBounds = GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -122.25, maxLat: 47.8)
		let global = try emptyArchive(bounds: region, minZoom: 0, maxZoom: 12)
		let regional = try emptyArchive(bounds: regionalBounds, minZoom: 13, maxZoom: 15)
		defer { [global, regional].forEach { try? FileManager.default.removeItem(at: $0) } }
		let store = TerrainStore()
		await store.configure(sources: [TerrainSource(globalURL: global, regionalURL: regional, bounds: region)])

		let west = TerrainStore.tilePixel(latitude: 47.55, longitude: -122.45, z: 14, size: 256)
		let east = TerrainStore.tilePixel(latitude: 47.55, longitude: -122.05, z: 14, size: 256)
		let away = TerrainStore.tilePixel(latitude: 40, longitude: -100, z: 14, size: 256)
		#expect(await store.dataMaxZoom(z: 14, x: west.x, y: west.y) == 15)
		#expect(await store.dataMaxZoom(z: 14, x: east.x, y: east.y) == 12)
		#expect(await store.dataMaxZoom(z: 14, x: away.x, y: away.y) == nil)
	}
}
