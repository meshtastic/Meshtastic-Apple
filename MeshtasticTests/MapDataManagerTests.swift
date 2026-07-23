// MapDataManagerTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

/// Covers `MapDataManager.importFromString` — the in-memory GeoJSON import path used by the
/// Site Planner native bridge (meshtastic/Meshtastic-Apple#2058).
@Suite("MapDataManager.importFromString", .serialized)
struct MapDataManagerImportFromStringTests {

	private let sampleGeoJSON = """
	{ "type": "FeatureCollection", "properties": { "name": "Coverage" }, "features": [
		{ "type": "Feature", "geometry": { "type": "Polygon", "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 0]]] },
		  "properties": { "fill": "#0080ff" } },
		{ "type": "Feature", "geometry": { "type": "Polygon", "coordinates": [[[2, 2], [3, 2], [3, 3], [2, 2]]] },
		  "properties": { "fill": "#00ff80" } }
	]}
	"""

	private func cleanUp(_ manager: MapDataManager, _ metadata: MapDataMetadata) async {
		try? await manager.deleteFile(metadata)
	}

	@Test func importsValidGeoJSONString() async throws {
		let manager = MapDataManager()
		let metadata = try await manager.importFromString(sampleGeoJSON, name: "Site Alpha \(UUID().uuidString)")
		defer { Task { await cleanUp(manager, metadata) } }

		#expect(metadata.overlayCount == 2)
		#expect(metadata.format == "geojson")
	}

	@Test func enforcesGeojsonExtensionAndSanitizesName() async throws {
		let manager = MapDataManager()
		// A name with path separators must not escape the temp directory or lose the extension.
		let metadata = try await manager.importFromString(sampleGeoJSON, name: "a/b:c \(UUID().uuidString)")
		defer { Task { await cleanUp(manager, metadata) } }

		#expect(metadata.filename.hasSuffix(".geojson"))
		#expect(!metadata.filename.contains("/"))
		#expect(!metadata.filename.contains(":"))
	}

	@Test func throwsOnInvalidGeoJSON() async throws {
		let manager = MapDataManager()
		await #expect(throws: Error.self) {
			try await manager.importFromString("not json at all", name: "bad")
		}
	}

	@Test func throwsOnOversizedString() async throws {
		let manager = MapDataManager()
		let huge = String(repeating: "x", count: 11 * 1024 * 1024) // > 10MB cap
		await #expect(throws: MapDataError.self) {
			try await manager.importFromString(huge, name: "huge")
		}
	}
}
