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

/// Covers file provenance and the per-source activation policy: a new Site Planner
/// run replaces the previous one (only the newest planner file stays active), while
/// manually uploaded files keep whatever visibility the user set.
@Suite("MapData source and visibility policy", .serialized)
struct MapDataSourcePolicyTests {

	private let sampleGeoJSON = """
	{ "type": "FeatureCollection", "features": [
		{ "type": "Feature", "geometry": { "type": "Polygon", "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 0]]] },
		  "properties": { "fill": "#0080ff" } }
	]}
	"""

	private func cleanUp(_ manager: MapDataManager, _ files: [MapDataMetadata]) async {
		for file in files {
			try? await manager.deleteFile(file)
		}
	}

	@Test func manifestsWithoutSourceDecodeAsManualUpload() throws {
		// A manifest entry written before `source` existed.
		let legacy = """
		{ "id": "9E8282D3-D73A-3954-8DD9-D5CAED9B4EFD", "filename": "a.geojson",
		  "originalName": "a", "uploadDate": 700000000, "fileSize": 10,
		  "format": "geojson", "overlayCount": 1, "isActive": true }
		"""
		let metadata = try JSONDecoder().decode(MapDataMetadata.self, from: Data(legacy.utf8))
		#expect(metadata.source == .manualUpload)
		#expect(metadata.isActive)
	}

	// Cleanup is awaited at the end of each test rather than launched from a defer:
	// an unstructured cleanup Task can still be rewriting upload_history.json when
	// the next serialized test starts. #expect failures are non-fatal in Swift
	// Testing, so the cleanup line is reached on assertion failure too.

	@Test func newPlannerRunDeactivatesOnlyOlderPlannerFiles() async throws {
		let manager = MapDataManager()
		var created: [MapDataMetadata] = []

		let manual = try await manager.importFromString(sampleGeoJSON, name: "Manual \(UUID().uuidString)")
		created.append(manual)
		let firstRun = try await manager.importFromString(sampleGeoJSON, name: "Run1 \(UUID().uuidString)", source: .sitePlanner)
		created.append(firstRun)
		let secondRun = try await manager.importFromString(sampleGeoJSON, name: "Run2 \(UUID().uuidString)", source: .sitePlanner)
		created.append(secondRun)

		let files = manager.getUploadedFiles()
		#expect(files.first(where: { $0.id == manual.id })?.isActive == true, "a planner run must not touch manual uploads")
		#expect(files.first(where: { $0.id == firstRun.id })?.isActive == false, "an older planner run is replaced")
		#expect(files.first(where: { $0.id == secondRun.id })?.isActive == true, "the newest planner run is the active one")
		#expect(files.first(where: { $0.id == secondRun.id })?.source == .sitePlanner)

		await cleanUp(manager, created)
	}

	@Test func manualUploadsArriveActiveAndKeepUserVisibility() async throws {
		let manager = MapDataManager()
		var created: [MapDataMetadata] = []

		let first = try await manager.importFromString(sampleGeoJSON, name: "Manual1 \(UUID().uuidString)")
		created.append(first)
		#expect(manager.getUploadedFiles().first(where: { $0.id == first.id })?.isActive == true)

		// The user hides it; a later manual upload must not resurrect or change it.
		manager.setFileActive(first.id, false)
		let second = try await manager.importFromString(sampleGeoJSON, name: "Manual2 \(UUID().uuidString)")
		created.append(second)

		let files = manager.getUploadedFiles()
		#expect(files.first(where: { $0.id == first.id })?.isActive == false, "user-set visibility survives later uploads")
		#expect(files.first(where: { $0.id == second.id })?.isActive == true)
		#expect(files.first(where: { $0.id == second.id })?.source == .manualUpload)

		// The hidden state must be in the manifest, not just this instance: a fresh
		// manager reading the same store has to agree, or a relaunch flips it back.
		let reloaded = MapDataManager()
		reloaded.loadMetadata()
		let reloadedFiles = reloaded.getUploadedFiles()
		#expect(reloadedFiles.first(where: { $0.id == first.id })?.isActive == false, "setFileActive must persist to the manifest")
		#expect(reloadedFiles.first(where: { $0.id == first.id })?.source == .manualUpload)

		await cleanUp(manager, created)
	}
}
