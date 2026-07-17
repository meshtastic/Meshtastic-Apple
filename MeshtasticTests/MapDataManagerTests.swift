// MapDataManagerTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

/// Stubs `URLSession` responses for `MapDataManager.importFromRemote` without touching the network.
private final class GeoJSONStubURLProtocol: URLProtocol {
	nonisolated(unsafe) static var statusCode = 200
	nonisolated(unsafe) static var responseData: Data = Data()

	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: Self.responseData)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}

	static func makeSession() -> URLSession {
		let config = URLSessionConfiguration.ephemeral
		config.protocolClasses = [GeoJSONStubURLProtocol.self]
		return URLSession(configuration: config)
	}
}

// Serialized: tests share mutable state on `GeoJSONStubURLProtocol` (its stubbed status/data are
// process-global, keyed by class not by request), so concurrent runs race and cross-contaminate.
@Suite("MapDataManager.importFromRemote", .serialized)
struct MapDataManagerImportFromRemoteTests {

	private let sampleGeoJSON = Data("""
	{ "type": "FeatureCollection", "features": [
		{ "type": "Feature", "geometry": { "type": "Polygon", "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 0]]] },
		  "properties": { "fill": "#0080ff" } },
		{ "type": "Feature", "geometry": { "type": "Polygon", "coordinates": [[[2, 2], [3, 2], [3, 3], [2, 2]]] },
		  "properties": { "fill": "#00ff80" } }
	]}
	""".utf8)

	/// Deletes anything the test imported so repeated runs don't accumulate files in the real Documents
	/// directory — `MapDataManager` has no injectable storage root, so cleanup has to happen here.
	private func cleanUp(_ manager: MapDataManager, _ metadata: MapDataMetadata) async {
		try? await manager.deleteFile(metadata)
	}

	@Test func downloadsAndImportsValidGeoJSON() async throws {
		GeoJSONStubURLProtocol.statusCode = 200
		GeoJSONStubURLProtocol.responseData = sampleGeoJSON

		let manager = MapDataManager()
		let metadata = try await manager.importFromRemote(
			urlString: "https://example.com/coverage-\(UUID().uuidString).geojson",
			session: GeoJSONStubURLProtocol.makeSession()
		)
		defer { Task { await cleanUp(manager, metadata) } }

		#expect(metadata.overlayCount == 2)
		#expect(metadata.format == "geojson")
	}

	@Test func throwsOnNonSuccessStatusCode() async throws {
		GeoJSONStubURLProtocol.statusCode = 404
		GeoJSONStubURLProtocol.responseData = Data()

		let manager = MapDataManager()
		await #expect(throws: Error.self) {
			try await manager.importFromRemote(
				urlString: "https://example.com/missing.geojson",
				session: GeoJSONStubURLProtocol.makeSession()
			)
		}
	}

	@Test func throwsOnOversizedDownload() async throws {
		GeoJSONStubURLProtocol.statusCode = 200
		GeoJSONStubURLProtocol.responseData = Data(repeating: 0, count: 11 * 1024 * 1024) // > 10MB cap

		let manager = MapDataManager()
		await #expect(throws: MapDataError.self) {
			try await manager.importFromRemote(
				urlString: "https://example.com/huge.geojson",
				session: GeoJSONStubURLProtocol.makeSession()
			)
		}
	}

	@Test func readsLocalFileURLWithoutNetworking() async throws {
		let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("local-\(UUID().uuidString).geojson")
		try sampleGeoJSON.write(to: tempURL)
		defer { try? FileManager.default.removeItem(at: tempURL) }

		let manager = MapDataManager()
		// No session is consulted for a `file://` URL — passing the stub session anyway proves that.
		let metadata = try await manager.importFromRemote(urlString: tempURL.absoluteString, session: GeoJSONStubURLProtocol.makeSession())
		defer { Task { await cleanUp(manager, metadata) } }

		#expect(metadata.overlayCount == 2)
	}
}

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
