//
//  OfflineMapImportTests.swift
//  MeshtasticTests
//

import Foundation
import SQLite3
import Testing

@testable import Meshtastic

@Suite("Offline map import")
struct OfflineMapImportTests {

	@Test func rasterPMTilesCreatesImportMetadata() throws {
		let metadata = try OfflineMapImportValidator.validate(header: rasterHeader, fileSize: 4_096)

		#expect(metadata.minZoom == 0)
		#expect(metadata.maxZoom == 15)
		#expect(metadata.bounds == GeoBounds(minLon: -119.3, minLat: 40.7, maxLon: -119.1, maxLat: 40.9))
	}

	@Test func vectorPMTilesCreatesImportMetadata() throws {
		let metadata = try OfflineMapImportValidator.validate(header: vectorHeader, fileSize: 4_096)

		#expect(metadata.maxZoom == 15)
	}

	@Test func mapOverThePerMapLimitIsRejected() {
		#expect(throws: OfflineMapImportError.self) {
			try OfflineMapImportValidator.validate(
				header: rasterHeader,
				fileSize: OfflineMapStorageLimits.maxRegionBytes + 1
			)
		}
	}

	@Test func validatesOnlyTheFixedHeaderFromADiskFile() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		let file = PMTilesExtractor.buildHeader(
			rootDirOffset: 127,
			rootDirLength: 0,
			metadataOffset: 127,
			metadataLength: 0,
			tileDataOffset: 127,
			tileDataLength: 0,
			numTiles: 0,
			bounds: GeoBounds(minLon: -119.3, minLat: 40.7, maxLon: -119.1, maxLat: 40.9),
			minZoom: 0,
			maxZoom: 15,
			tileType: .png,
			tileCompression: .none
		)
		try file.write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let metadata = try OfflineMapImportValidator.validate(fileURL: url)

		#expect(metadata.maxZoom == 15)
	}

	@Test func MBTilesCreatesImportMetadata() throws {
		let url = try makeMBTilesFixture()
		defer { try? FileManager.default.removeItem(at: url) }

		let metadata = try OfflineMapImportValidator.validate(fileURL: url)

		#expect(metadata.minZoom == 3)
		#expect(metadata.maxZoom == 14)
		#expect(metadata.bounds == GeoBounds(minLon: -119.3, minLat: 40.7, maxLon: -119.1, maxLat: 40.9))
	}

	@MainActor
	@Test func importCopiesTheSharedArchiveIntoTheManagedStore() async throws {
		let sourceURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("Shared Playa \(UUID().uuidString).pmtiles")
		var archive = PMTilesExtractor.buildHeader(
			rootDirOffset: 127,
			rootDirLength: 0,
			metadataOffset: 127,
			metadataLength: 0,
			tileDataOffset: 127,
			tileDataLength: 0,
			numTiles: 0,
			bounds: GeoBounds(minLon: -119.3, minLat: 40.7, maxLon: -119.1, maxLat: 40.9),
			minZoom: 0,
			maxZoom: 15,
			tileType: .png,
			tileCompression: .none
		)
		archive.append(Data(UUID().uuidString.utf8))
		try archive.write(to: sourceURL)
		defer { try? FileManager.default.removeItem(at: sourceURL) }

		let manager = OfflineMapManager.shared
		let imported = try await manager.importOfflineMap(from: sourceURL)
		defer { manager.remove(imported) }

		#expect(imported.name == sourceURL.deletingPathExtension().lastPathComponent)
		#expect(imported.sourceBuild == "Imported")
		#expect(manager.fileURL(for: imported).map { FileManager.default.fileExists(atPath: $0.path) } == true)
	}

	@MainActor
	@Test func importPreservesMBTilesExtension() async throws {
		let sourceURL = try makeMBTilesFixture()
		defer { try? FileManager.default.removeItem(at: sourceURL) }

		let manager = OfflineMapManager.shared
		let imported = try await manager.importOfflineMap(from: sourceURL)
		defer { manager.remove(imported) }

		#expect(imported.fileName.hasSuffix(".mbtiles"))
	}

	private var rasterHeader: PMTilesHeader {
		parseHeader(tileType: .png)
	}

	private var vectorHeader: PMTilesHeader {
		parseHeader(tileType: .mvt)
	}

	private func parseHeader(tileType: PMTilesTileType) -> PMTilesHeader {
		let data = PMTilesExtractor.buildHeader(
			rootDirOffset: 127,
			rootDirLength: 0,
			metadataOffset: 127,
			metadataLength: 0,
			tileDataOffset: 127,
			tileDataLength: 0,
			numTiles: 0,
			bounds: GeoBounds(minLon: -119.3, minLat: 40.7, maxLon: -119.1, maxLat: 40.9),
			minZoom: 0,
			maxZoom: 15,
			tileType: tileType,
			tileCompression: .none
		)
		return PMTilesArchive.parseHeader(data)!
	}

	private func makeMBTilesFixture() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("\(UUID().uuidString).mbtiles")
		var database: OpaquePointer?
		guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
			throw OfflineMapImportError.unreadableFile
		}
		defer { sqlite3_close(database) }

		let sql = """
		CREATE TABLE metadata (name TEXT, value TEXT);
		CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
		INSERT INTO metadata VALUES
			('minzoom', '3'),
			('maxzoom', '14'),
			('bounds', '-119.3,40.7,-119.1,40.9'),
			('format', 'png');
		INSERT INTO tiles VALUES (3, 1, 1, X'89504E47');
		"""
		guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
			throw OfflineMapImportError.unreadableFile
		}
		return url
	}
}
