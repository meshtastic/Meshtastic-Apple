//
//  TerrainDownloadTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/15/26.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Terrain download")
struct TerrainDownloadTests {

	/// Seattle-ish bbox that sits inside a single z6 tile.
	private let bounds = GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -122.0, maxLat: 47.8)

	private func makeRegion(fileName: String = "\(UUID().uuidString).pmtiles", terrain: OfflineMapTerrain? = nil) -> OfflineMapRegion {
		OfflineMapRegion(
			name: "Seattle",
			fileName: fileName,
			bounds: bounds,
			minZoom: 0,
			maxZoom: 13,
			fileSize: 1_024,
			createdDate: Date(timeIntervalSinceReferenceDate: 700_000_000),
			updatedDate: Date(timeIntervalSinceReferenceDate: 700_000_000),
			sourceBuild: "20260801",
			terrain: terrain
		)
	}

	// MARK: - Codable

	@Test func regionRoundTripsWithTerrain() throws {
		let terrain = OfflineMapTerrain(
			fileName: "abc-terrain.pmtiles",
			regionalFileName: "abc-terrain-hi.pmtiles",
			byteCount: 12_345_678,
			downloadedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
			maxZoom: 15
		)
		let region = makeRegion(terrain: terrain)

		let data = try JSONEncoder().encode(region)
		let decoded = try JSONDecoder().decode(OfflineMapRegion.self, from: data)

		#expect(decoded == region)
		#expect(decoded.terrain?.fileName == "abc-terrain.pmtiles")
		#expect(decoded.terrain?.regionalFileName == "abc-terrain-hi.pmtiles")
		#expect(decoded.terrain?.byteCount == 12_345_678)
		#expect(decoded.terrain?.maxZoom == 15)
	}

	@Test func regionRoundTripsWithoutTerrain() throws {
		let region = makeRegion()

		let data = try JSONEncoder().encode(region)
		let decoded = try JSONDecoder().decode(OfflineMapRegion.self, from: data)

		#expect(decoded == region)
		#expect(decoded.terrain == nil)
	}

	@Test func oldManifestWithoutTerrainFieldDecodes() throws {
		// A manifest entry written before terrain support existed — no `terrain` key.
		let json = """
		{
			"id": "E3B0C442-98FC-1C14-9AFB-F4C8996FB924",
			"name": "Old Region",
			"fileName": "old.pmtiles",
			"minLongitude": -122.5,
			"minLatitude": 47.3,
			"maxLongitude": -122.0,
			"maxLatitude": 47.8,
			"minZoom": 0,
			"maxZoom": 13,
			"fileSize": 2048,
			"createdDate": 700000000,
			"updatedDate": 700000000,
			"sourceBuild": "20260101"
		}
		"""

		let decoded = try JSONDecoder().decode(OfflineMapRegion.self, from: Data(json.utf8))

		#expect(decoded.terrain == nil)
		#expect(decoded.name == "Old Region")
		#expect(decoded.fileName == "old.pmtiles")
		#expect(decoded.maxZoom == 13)
	}

	// MARK: - Regional archive tile math

	@Test func cityScaleBoundsIntersectASingleZ6Tile() {
		let tiles = OfflineMapManager.z6Tiles(intersecting: bounds)

		#expect(tiles.count == 1)
		#expect(tiles.first?.x == 10)
		#expect(tiles.first?.y == 22)
	}

	@Test func wideBoundsIntersectMultipleZ6Tiles() {
		// Spans two z6 columns — a z6 tile is 5.625° of longitude.
		let wide = GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -116.0, maxLat: 47.8)

		let tiles = OfflineMapManager.z6Tiles(intersecting: wide)

		#expect(tiles.count == 2)
		#expect(tiles.map { $0.x }.sorted() == [10, 11])
		#expect(tiles.allSatisfy { $0.y == 22 })
	}

	// MARK: - File naming

	@Test func terrainFileNamesDeriveFromTheBasemapArchive() {
		let names = OfflineMapManager.terrainFileNames(forBasemap: "ABC123.pmtiles")

		#expect(names.global == "ABC123-terrain.pmtiles")
		#expect(names.regional == "ABC123-terrain-hi.pmtiles")
	}

	// MARK: - Removal

	@MainActor
	@Test func removeDeletesTerrainFilesWithTheRegion() throws {
		let manager = OfflineMapManager.shared
		manager.loadIfNeeded()
		let dir = try #require(manager.directoryURL())

		let fileName = "\(UUID().uuidString).pmtiles"
		let names = OfflineMapManager.terrainFileNames(forBasemap: fileName)
		let basemapURL = dir.appendingPathComponent(fileName)
		let globalURL = dir.appendingPathComponent(names.global)
		let regionalURL = dir.appendingPathComponent(names.regional)
		try Data("basemap".utf8).write(to: basemapURL)
		try Data("terrain".utf8).write(to: globalURL)
		try Data("terrain-hi".utf8).write(to: regionalURL)

		let region = makeRegion(
			fileName: fileName,
			terrain: OfflineMapTerrain(
				fileName: names.global,
				regionalFileName: names.regional,
				byteCount: 17,
				downloadedAt: .now,
				maxZoom: 15
			)
		)
		manager.add(region)
		defer { manager.remove(region) }
		#expect(manager.terrainSources().contains { $0.globalURL == globalURL && $0.regionalURL == regionalURL })

		manager.remove(region)

		#expect(!FileManager.default.fileExists(atPath: basemapURL.path))
		#expect(!FileManager.default.fileExists(atPath: globalURL.path))
		#expect(!FileManager.default.fileExists(atPath: regionalURL.path))
		#expect(!manager.regions.contains { $0.id == region.id })
		#expect(!manager.terrainSources().contains { $0.globalURL == globalURL })
	}
}
