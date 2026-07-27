//
//  OfflineMapImportTests.swift
//  MeshtasticTests
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Offline PMTiles import")
struct OfflineMapImportTests {

	@Test func rasterPMTilesCreatesImportMetadata() throws {
		let metadata = try OfflineMapImportValidator.validate(header: rasterHeader, fileSize: 4_096)

		#expect(metadata.minZoom == 0)
		#expect(metadata.maxZoom == 15)
		#expect(metadata.bounds == GeoBounds(minLon: -119.3, minLat: 40.7, maxLon: -119.1, maxLat: 40.9))
	}

	@Test func vectorPMTilesIsRejected() {
		#expect(throws: OfflineMapImportError.self) {
			try OfflineMapImportValidator.validate(header: vectorHeader, fileSize: 4_096)
		}
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

	@MainActor
	@Test func importCopiesTheSharedArchiveIntoTheManagedStore() throws {
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
		let imported = try manager.importPMTiles(from: sourceURL)
		defer { manager.remove(imported) }

		#expect(imported.name == sourceURL.deletingPathExtension().lastPathComponent)
		#expect(imported.sourceBuild == "Imported")
		#expect(manager.fileURL(for: imported).map { FileManager.default.fileExists(atPath: $0.path) } == true)
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
}
