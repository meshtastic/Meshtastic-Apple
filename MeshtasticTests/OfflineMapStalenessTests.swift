//
//  OfflineMapStalenessTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Offline map provenance and staleness")
struct OfflineMapStalenessTests {

	/// Seattle: inside the single z6 tile 6-10-22.
	private let bounds = GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -122.0, maxLat: 47.8)
	private let globalURL = URL(string: OfflineMapManager.terrainGlobalArchive)!
	private let regionalURL = URL(string: "https://download.mapterhorn.com/6-10-22.pmtiles")!

	private func terrain(globalETag: String?, regionalETag: String? = nil, regional: Bool = false) -> OfflineMapTerrain {
		OfflineMapTerrain(
			fileName: "abc-terrain.pmtiles",
			regionalFileName: regional ? "abc-terrain-hi.pmtiles" : nil,
			byteCount: 1,
			downloadedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
			maxZoom: regional ? 15 : 12,
			globalETag: globalETag,
			regionalETag: regionalETag
		)
	}

	/// Answers the 16 KiB check with the given current ETag per archive; a missing URL is
	/// a network failure.
	private func extractor(_ current: [URL: String?]) -> PMTilesExtractor {
		PMTilesExtractor { url, range, _ in
			guard let etag = current[url] else { throw URLError(.notConnectedToInternet) }
			let body = Data(repeating: 0, count: Int(range.upperBound - range.lowerBound + 1))
			var headers = ["Content-Range": "bytes \(range.lowerBound)-\(range.upperBound)/999999"]
			headers["ETag"] = etag
			return .init(statusCode: 206, headers: headers, body: body)
		}
	}

	private func staleness(_ terrain: OfflineMapTerrain, _ current: [URL: String?]) async -> OfflineMapStaleness {
		await OfflineMapManager.terrainStaleness(of: terrain, bounds: bounds, extractor: extractor(current))
	}

	@Test func sameETagIsFresh() async {
		#expect(await staleness(terrain(globalETag: "\"g-1\""), [globalURL: "\"g-1\""]) == .fresh)
	}

	@Test func changedGlobalETagIsStale() async {
		#expect(await staleness(terrain(globalETag: "\"g-1\""), [globalURL: "\"g-2\""]) == .stale)
	}

	@Test func changedRegionalETagIsStale() async {
		let terrain = terrain(globalETag: "\"g-1\"", regionalETag: "\"r-1\"", regional: true)
		#expect(await staleness(terrain, [globalURL: "\"g-1\"", regionalURL: "\"r-2\""]) == .stale)
	}

	@Test func regionalAndGlobalUnchangedIsFresh() async {
		let terrain = terrain(globalETag: "\"g-1\"", regionalETag: "\"r-1\"", regional: true)
		#expect(await staleness(terrain, [globalURL: "\"g-1\"", regionalURL: "\"r-1\""]) == .fresh)
	}

	@Test func nothingRecordedIsUnknown() async {
		#expect(await staleness(terrain(globalETag: nil), [globalURL: "\"g-1\""]) == .unknown)
	}

	@Test func hostWithoutETagIsUnknown() async {
		#expect(await staleness(terrain(globalETag: "\"g-1\""), [globalURL: String?.none]) == .unknown)
	}

	@Test func unreachableHostIsUnknown() async {
		#expect(await staleness(terrain(globalETag: "\"g-1\""), [:]) == .unknown)
	}

	@Test func terrainProvenanceRoundTrips() throws {
		var terrain = terrain(globalETag: "\"g-1\"", regionalETag: "\"r-1\"", regional: true)
		terrain.globalLastModified = Date(timeIntervalSince1970: 1_789_138_702)
		let region = OfflineMapRegion(
			name: "Seattle", fileName: "abc.pmtiles", bounds: bounds, minZoom: 0, maxZoom: 13,
			fileSize: 1, sourceBuild: "20261030", sourceETag: "\"b-1\"", terrain: terrain
		)
		let decoded = try JSONDecoder().decode(OfflineMapRegion.self, from: JSONEncoder().encode(region))
		#expect(decoded == region)
		#expect(decoded.sourceETag == "\"b-1\"")
		#expect(decoded.terrain?.regionalETag == "\"r-1\"")
	}

	@Test func manifestWithoutProvenanceDecodesAsUnknown() throws {
		let json = """
		{
			"id": "E3B0C442-98FC-1C14-9AFB-F4C8996FB924",
			"name": "Old Region", "fileName": "old.pmtiles",
			"minLongitude": -122.5, "minLatitude": 47.3, "maxLongitude": -122.0, "maxLatitude": 47.8,
			"minZoom": 0, "maxZoom": 13, "fileSize": 2048,
			"createdDate": 700000000, "updatedDate": 700000000, "sourceBuild": "20260101",
			"terrain": { "fileName": "old-terrain.pmtiles", "byteCount": 10, "downloadedAt": 700000000, "maxZoom": 12 }
		}
		"""
		let decoded = try JSONDecoder().decode(OfflineMapRegion.self, from: Data(json.utf8))
		#expect(decoded.sourceETag == nil)
		#expect(decoded.terrain?.globalETag == nil)
		#expect(decoded.terrain?.globalLastModified == nil)
		#expect(decoded.terrain?.regionalETag == nil)
	}
}

/// The real `URLSession` fetcher against a host that ignores `Range` and sends the whole file.
@Suite("Range fetcher against a host that ignores Range", .serialized)
struct PMTilesRangeFetcherTests {

	/// Answers every request with 200 and a 64 MiB body in 64 KiB chunks, counting what it sent.
	final class WholeFileProtocol: URLProtocol, @unchecked Sendable {
		static let chunk = Data(repeating: 7, count: 64 << 10)
		static let chunkCount = 1_024
		nonisolated(unsafe) static var sentChunks = 0
		private let lock = NSLock()
		private var stopped = false

		override static func canInit(with request: URLRequest) -> Bool { true }
		override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

		override func startLoading() {
			Self.sentChunks = 0
			guard let url = request.url, let client else { return }
			let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["ETag": "\"v2\""])!
			client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
			DispatchQueue.global().async {
				for _ in 0..<Self.chunkCount {
					if self.lock.withLock({ self.stopped }) { return }
					client.urlProtocol(self, didLoad: Self.chunk)
					Self.sentChunks += 1
					Thread.sleep(forTimeInterval: 0.001)
				}
				client.urlProtocolDidFinishLoading(self)
			}
		}

		override func stopLoading() {
			lock.withLock { stopped = true }
		}
	}

	@Test("a 16 KiB check stops reading instead of taking the whole file")
	func boundedWholeFile() async throws {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [WholeFileProtocol.self]
		let extractor = PMTilesExtractor(session: URLSession(configuration: configuration))
		let etag = try await extractor.currentETag(of: URL(string: "https://example.com/planet.pmtiles")!)
		#expect(etag == "\"v2\"")
		// Give the stub a moment to see the cancel, then check it stopped long before the end.
		try await Task.sleep(for: .milliseconds(100))
		#expect(WholeFileProtocol.sentChunks < WholeFileProtocol.chunkCount / 4)
	}
}
