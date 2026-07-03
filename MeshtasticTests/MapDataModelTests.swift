// MapDataModelTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

// MARK: - MapDataMetadata Tests

@Suite("MapDataMetadata")
struct MapDataMetadataTests {

	private func makeMetadata(
		filename: String = "test.geojson",
		originalName: String = "test",
		uploadDate: Date = Date(),
		fileSize: Int64 = 1024,
		format: String = "geojson",
		license: String? = nil,
		attribution: String? = nil,
		overlayCount: Int = 5,
		isActive: Bool = false
	) -> MapDataMetadata {
		MapDataMetadata(
			filename: filename,
			originalName: originalName,
			uploadDate: uploadDate,
			fileSize: fileSize,
			format: format,
			license: license,
			attribution: attribution,
			overlayCount: overlayCount,
			isActive: isActive
		)
	}

	@Test func init_setsProperties() {
		let date = Date()
		let m = makeMetadata(
			filename: "data.json",
			originalName: "data",
			uploadDate: date,
			fileSize: 2048,
			format: "json",
			license: "MIT",
			attribution: "Test",
			overlayCount: 10,
			isActive: true
		)
		#expect(m.filename == "data.json")
		#expect(m.originalName == "data")
		#expect(m.uploadDate == date)
		#expect(m.fileSize == 2048)
		#expect(m.format == "json")
		#expect(m.license == "MIT")
		#expect(m.attribution == "Test")
		#expect(m.overlayCount == 10)
		#expect(m.isActive == true)
	}

	@Test func id_isUnique() {
		let m1 = makeMetadata()
		let m2 = makeMetadata()
		#expect(m1.id != m2.id)
	}

	@Test func fileSizeString_KB() {
		let m = makeMetadata(fileSize: 1024)
		let str = m.fileSizeString
		#expect(str.contains("KB") || str.contains("kB") || str.contains("bytes"))
	}

	@Test func fileSizeString_MB() {
		let m = makeMetadata(fileSize: 5 * 1024 * 1024)
		let str = m.fileSizeString
		#expect(str.contains("MB"))
	}

	@Test func fileSizeString_zero() {
		let m = makeMetadata(fileSize: 0)
		let str = m.fileSizeString
		#expect(!str.isEmpty)
	}

	@Test func codable_roundTrip() throws {
		let original = makeMetadata(
			filename: "test_123.geojson",
			originalName: "test",
			fileSize: 4096,
			format: "geojson",
			license: "CC-BY",
			attribution: "OSM",
			overlayCount: 3,
			isActive: true
		)
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(MapDataMetadata.self, from: data)
		#expect(decoded.filename == original.filename)
		#expect(decoded.originalName == original.originalName)
		#expect(decoded.fileSize == original.fileSize)
		#expect(decoded.format == original.format)
		#expect(decoded.license == original.license)
		#expect(decoded.attribution == original.attribution)
		#expect(decoded.overlayCount == original.overlayCount)
		#expect(decoded.isActive == original.isActive)
		#expect(decoded.id == original.id)
	}

	@Test func isActive_canBeToggled() {
		var m = makeMetadata(isActive: false)
		#expect(m.isActive == false)
		m.isActive = true
		#expect(m.isActive == true)
	}
}

// MARK: - MapDataError Tests

@Suite("MapDataError")
struct MapDataErrorTests {

	@Test func fileTooLarge_description() {
		let err = MapDataError.fileTooLarge
		#expect(err.errorDescription?.contains("10MB") == true)
	}

	@Test func invalidFileType_description() {
		let err = MapDataError.invalidFileType
		#expect(err.errorDescription != nil)
		#expect(!err.errorDescription!.isEmpty)
	}

	@Test func unsupportedFormat_description() {
		let err = MapDataError.unsupportedFormat
		#expect(err.errorDescription != nil)
	}

	@Test func invalidContent_description() {
		let err = MapDataError.invalidContent
		#expect(err.errorDescription != nil)
	}

	@Test func directoryCreationFailed_description() {
		let err = MapDataError.directoryCreationFailed
		#expect(err.errorDescription != nil)
	}

	@Test func invalidDestination_description() {
		let err = MapDataError.invalidDestination
		#expect(err.errorDescription != nil)
	}

	@Test func fileNotFound_description() {
		let err = MapDataError.fileNotFound
		#expect(err.errorDescription != nil)
	}

	@Test func saveFailed_description() {
		let err = MapDataError.saveFailed
		#expect(err.errorDescription != nil)
	}

	@Test func allCases_haveNonEmptyDescriptions() {
		let errors: [MapDataError] = [
			.fileTooLarge, .invalidFileType, .unsupportedFormat, .invalidContent,
			.directoryCreationFailed, .invalidDestination, .fileNotFound, .saveFailed
		]
		for err in errors {
			#expect(err.errorDescription != nil, "Expected \(err) to have a description")
			#expect(!err.errorDescription!.isEmpty)
		}
	}
}

// MARK: - PersistenceError Tests

@Suite("PersistenceError Descriptions")
struct PersistenceErrorDescriptionTests {

	@Test func invalidInput_description() {
		let err = PersistenceError.invalidInput(message: "test message")
		#expect(err.errorDescription?.contains("test message") == true)
	}

	@Test func saveFailed_description() {
		let err = PersistenceError.saveFailed(message: "save error")
		#expect(err.errorDescription?.contains("save error") == true)
	}

	@Test func entityCreationFailed_description() {
		let err = PersistenceError.entityCreationFailed(message: "creation failed")
		#expect(err.errorDescription?.contains("creation failed") == true)
	}
}

// MARK: - Notification Struct Tests

@Suite("Notification Model")
struct NotificationModelTests {

	@Test func init_requiredProperties() {
		let n = Notification(id: "test-1", title: "Title", subtitle: "Sub", content: "Body")
		#expect(n.id == "test-1")
		#expect(n.title == "Title")
		#expect(n.subtitle == "Sub")
		#expect(n.content == "Body")
		#expect(n.target == nil)
		#expect(n.path == nil)
		#expect(n.messageId == nil)
		#expect(n.channel == nil)
		#expect(n.userNum == nil)
		#expect(n.critical == false)
	}

	@Test func init_allProperties() {
		let n = Notification(
			id: "test-2",
			title: "Alert",
			subtitle: "Warning",
			content: "Low battery",
			target: "node",
			path: "/nodes/123",
			messageId: 42,
			channel: 1,
			userNum: 9999,
			critical: true
		)
		#expect(n.target == "node")
		#expect(n.path == "/nodes/123")
		#expect(n.messageId == 42)
		#expect(n.channel == 1)
		#expect(n.userNum == 9999)
		#expect(n.critical == true)
	}
}

// MARK: - Offline Vector Basemap Performance

// Benchmark intentionally prints its measurements to the test log for perf tuning.
// swiftlint:disable disable_print

/// Headless benchmark for the offline Protomaps vector decode + road stitching pipeline.
/// Drives quantitative perf tuning (overlay count is the dominant SwiftUI-Map cost).
/// Reads the local `bellevue.pmtiles`; skips cleanly if it isn't present.
@MainActor
@Suite("Offline Vector Basemap Perf")
struct OfflineVectorPerfTests {

	/// Repo-relative so it works on any clone (the file lives at the repo root, two levels up from
	/// this test source). Read via the build machine's path — the simulator can reach host paths.
	private var bellevueURL: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()      // MeshtasticTests/
			.deletingLastPathComponent()      // repo root
			.appendingPathComponent("bellevue.pmtiles")
	}

	@Test("decode + stitch Bellevue — zoom sweep")
	func benchmark() throws {
		let url = bellevueURL
		guard FileManager.default.fileExists(atPath: url.path) else {
			print("OFFLINE-PERF: bellevue.pmtiles not found at \(url.path) — skipping")
			return
		}
		// Zoom sweep (no clutter filtering).
		for maxTiles in [8, 16, 48] {
			if let stats = OfflineVectorTileProvider.measure(url: url, maxTiles: maxTiles, minFillMeters: 0, minRoadMeters: 0) {
				print("OFFLINE-PERF[z-sweep maxTiles=\(maxTiles)]: \(stats)")
			}
		}
		// Clutter-filter sweep at z13 (maxTiles=16) — drop tiny fills + short road stubs.
		for threshold in [(0.0, 0.0), (25.0, 30.0), (40.0, 60.0), (60.0, 100.0)] {
			if let stats = OfflineVectorTileProvider.measure(url: url, maxTiles: 16, minFillMeters: threshold.0, minRoadMeters: threshold.1) {
				print("OFFLINE-PERF[z13 fill≥\(Int(threshold.0))m road≥\(Int(threshold.1))m]: \(stats)")
			}
		}
		#expect(true)
	}
}

// swiftlint:enable disable_print
