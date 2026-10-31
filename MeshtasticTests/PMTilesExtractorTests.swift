// PMTilesExtractorTests.swift
// MeshtasticTests
//
// Validates the PMTiles v3 writer against the existing reader (PMTilesArchive)
// and the tile-enumeration math — no network required.

import Testing
import Foundation
@testable import Meshtastic

@Suite("PMTilesExtractor tile math")
struct PMTilesExtractorTileMathTests {

	@Test func tileXY_atZoomZero_isOrigin() {
		#expect(PMTilesExtractor.tileXY(lon: -122.2, lat: 47.6, z: 0) == (0, 0))
		#expect(PMTilesExtractor.tileXY(lon: 150, lat: -40, z: 0) == (0, 0))
	}

	@Test func tileXY_atZoomOne_quadrants() {
		// Pacific NW → north-west quadrant.
		#expect(PMTilesExtractor.tileXY(lon: -122.2, lat: 47.6, z: 1) == (0, 0))
		// East of prime meridian, southern hemisphere → south-east quadrant.
		#expect(PMTilesExtractor.tileXY(lon: 10, lat: -20, z: 1) == (1, 1))
	}

	@Test func tileXY_clampsExtremeLatitude() {
		let (_, y) = PMTilesExtractor.tileXY(lon: 0, lat: 89, z: 4)
		#expect(y == 0) // clamped to the Web-Mercator limit, top row
	}

	@Test func roughByteEstimate_weightsHighZoomTilesLighter() {
		let bounds = GeoBounds(minLon: -122.5, minLat: 47.4, maxLon: -122.2, maxLat: 47.8)
		let standard = PMTilesExtractor.roughByteEstimate(in: bounds, minZoom: 0, maxZoom: 13)
		let high = PMTilesExtractor.roughByteEstimate(in: bounds, minZoom: 0, maxZoom: 15)
		#expect(high > standard)
		// z14/z15 tiles average far smaller than mid-zoom tiles; the high-detail
		// increment must reflect that rather than a flat per-tile constant.
		let addedTiles = PMTilesExtractor.tileCount(in: bounds, minZoom: 14, maxZoom: 15)
		let flatIncrement = Int64(addedTiles) * 34_816
		#expect(high - standard < flatIncrement)
	}

	@Test func tileCount_matchesEnumeratedIDs() {
		let bounds = GeoBounds(minLon: -122.3, minLat: 47.4, maxLon: -122.0, maxLat: 47.7)
		let count = PMTilesExtractor.tileCount(in: bounds, minZoom: 0, maxZoom: 12)
		let ids = PMTilesExtractor.tileIDs(in: bounds, minZoom: 0, maxZoom: 12)
		#expect(count == ids.count)
		#expect(count > 0)
	}

	@Test func tileIDs_areUniquePerZoom() {
		let bounds = GeoBounds(minLon: -1, minLat: -1, maxLon: 1, maxLat: 1)
		let ids = PMTilesExtractor.tileIDs(in: bounds, minZoom: 0, maxZoom: 8)
		#expect(Set(ids).count == ids.count)
	}
}

@Suite("PMTiles directory round-trip")
struct PMTilesDirectoryRoundTripTests {

	@Test func deserializeDirectory_rejectsZeroFirstOffset() {
		// count=1, then tileID/runLength/length/offset values of 0. The first
		// offset is invalid in PMTiles (zero is only a continuation marker).
		#expect(PMTilesArchive.deserializeDirectory(Data([1, 0, 0, 0, 0])).isEmpty)
	}

	@Test func serializeDeserialize_preservesEntries() {
		let entries: [PMTilesArchive.Entry] = [
			.init(tileID: 5, offset: 0, length: 100, runLength: 1),
			.init(tileID: 9, offset: 100, length: 250, runLength: 1),
			.init(tileID: 42, offset: 350, length: 17, runLength: 1)
		].sorted { $0.tileID < $1.tileID }

		let data = PMTilesExtractor.serializeDirectory(entries)
		let decoded = PMTilesArchive.deserializeDirectory(data)

		#expect(decoded.count == entries.count)
		for (a, b) in zip(entries, decoded) {
			#expect(a.tileID == b.tileID)
			#expect(a.offset == b.offset)
			#expect(a.length == b.length)
			#expect(a.runLength == b.runLength)
		}
	}
}

@Suite("PMTiles header round-trip")
struct PMTilesHeaderRoundTripTests {

	@Test func parseHeader_rejectsTruncatedVersionedHeader() {
		var truncated = Data("PMTiles".utf8)
		truncated.append(3)
		#expect(PMTilesArchive.parseHeader(truncated) == nil)
	}

	@Test func buildParse_preservesFields() throws {
		let bounds = GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -121.9, maxLat: 47.8)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: 64,
			metadataOffset: 191, metadataLength: 32,
			tileDataOffset: 223, tileDataLength: 4096,
			numTiles: 12, bounds: bounds, minZoom: 0, maxZoom: 14,
			tileType: .mvt, tileCompression: .gzip
		)
		let parsed = try #require(PMTilesArchive.parseHeader(header))

		#expect(parsed.rootDirOffset == 127)
		#expect(parsed.rootDirLength == 64)
		#expect(parsed.tileDataOffset == 223)
		#expect(parsed.minZoom == 0)
		#expect(parsed.maxZoom == 14)
		#expect(parsed.tileType == .mvt)
		#expect(parsed.tileCompression == .gzip)
		#expect(parsed.internalCompression == .none)
		#expect(abs(parsed.bounds.minLon - bounds.minLon) < 1e-6)
		#expect(abs(parsed.bounds.maxLat - bounds.maxLat) < 1e-6)
	}
}

@Suite("PMTiles full file round-trip")
struct PMTilesFullFileRoundTripTests {

	@Test func archiveWithOutOfRangeDirectoryOffsetDoesNotReadTile() throws {
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: .max, rootDirLength: 1,
			metadataOffset: 127, metadataLength: 0,
			tileDataOffset: 127, tileDataLength: 0,
			numTiles: 0,
			bounds: GeoBounds(minLon: -1, minLat: -1, maxLon: 1, maxLat: 1),
			minZoom: 0, maxZoom: 0, tileType: .png, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try header.write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let archive = try #require(PMTilesArchive(url: url))
		#expect(archive.tileData(z: 0, x: 0, y: 0) == nil)
	}

	@Test func archiveWithOverflowingTileDataOffsetDoesNotReadTile() throws {
		let directory = PMTilesExtractor.serializeDirectory([
			.init(tileID: 0, offset: 1, length: 1, runLength: 1)
		])
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(directory.count),
			metadataOffset: 127 + UInt64(directory.count), metadataLength: 0,
			tileDataOffset: .max, tileDataLength: 0,
			numTiles: 1,
			bounds: GeoBounds(minLon: -1, minLat: -1, maxLon: 1, maxLat: 1),
			minZoom: 0, maxZoom: 0, tileType: .png, tileCompression: .none
		)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try (header + directory).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let archive = try #require(PMTilesArchive(url: url))
		#expect(archive.tileData(z: 0, x: 0, y: 0) == nil)
	}

	@Test func writtenArchive_readsBackTiles() throws {
		// Build a small archive the way PMTilesExtractor.extract does, with uncompressed
		// payloads, then open it with PMTilesArchive and read every tile back.
		struct Tile { let z: UInt8; let x: UInt32; let y: UInt32; let payload: Data }
		let tiles: [Tile] = [
			.init(z: 10, x: 163, y: 357, payload: Data("tile-a".utf8)),
			.init(z: 12, x: 654, y: 1431, payload: Data("payload-b-longer".utf8)),
			.init(z: 14, x: 2620, y: 5725, payload: Data("c".utf8))
		]

		var tileData = Data()
		var entries: [PMTilesArchive.Entry] = []
		for tile in tiles {
			let id = PMTilesArchive.zxyToTileID(z: tile.z, x: tile.x, y: tile.y)
			entries.append(.init(tileID: id, offset: UInt64(tileData.count), length: UInt32(tile.payload.count), runLength: 1))
			tileData.append(tile.payload)
		}
		entries.sort { $0.tileID < $1.tileID }

		let root = PMTilesExtractor.serializeDirectory(entries)
		let metadata = PMTilesExtractor.metadataJSON()
		let tileDataOffset = UInt64(127 + root.count + metadata.count)
		let header = PMTilesExtractor.buildHeader(
			rootDirOffset: 127, rootDirLength: UInt64(root.count),
			metadataOffset: UInt64(127 + root.count), metadataLength: UInt64(metadata.count),
			tileDataOffset: tileDataOffset, tileDataLength: UInt64(tileData.count),
			numTiles: UInt64(entries.count),
			bounds: GeoBounds(minLon: -122.5, minLat: 47.3, maxLon: -121.9, maxLat: 47.8),
			minZoom: 10, maxZoom: 14, tileType: .png, tileCompression: .none
		)

		var file = Data()
		file.append(header)
		file.append(root)
		file.append(metadata)
		file.append(tileData)

		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try file.write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		let archive = try #require(PMTilesArchive(url: url))
		for tile in tiles {
			let read = archive.tileData(z: tile.z, x: tile.x, y: tile.y)
			#expect(read == tile.payload)
		}
		// A tile that was never written must not resolve.
		#expect(archive.tileData(z: 14, x: 0, y: 0) == nil)
	}
}

@Suite("PMTilesExtractor directory cache")
struct PMTilesExtractorDirectoryCacheTests {

	private let world = GeoBounds(minLon: -180, minLat: -85, maxLon: 180, maxLat: 85)
	private let planetURL = URL(fileURLWithPath: "/planet.pmtiles")
	private let regionalURL = URL(fileURLWithPath: "/6-10-22.pmtiles")

	/// Two archives whose root directories both sit at offset 127, as every PMTiles
	/// file's does: the planet holds only z0, the regional archive only z1.
	private func extractor() -> PMTilesExtractor {
		let archives = [
			planetURL: makeArchive(tiles: [ArchiveTile(z: 0, x: 0, y: 0, payload: Data("planet".utf8))], minZoom: 0, maxZoom: 0),
			regionalURL: makeArchive(tiles: [ArchiveTile(z: 1, x: 0, y: 0, payload: Data("regional".utf8))], minZoom: 1, maxZoom: 1)
		]
		return PMTilesExtractor { url, range, _ in
			guard let data = archives[url] else { return .init(statusCode: 404, body: Data()) }
			let start = Int(range.lowerBound)
			guard start < data.count else { return .init(statusCode: 416, body: Data()) }
			let end = min(Int(range.upperBound), data.count - 1)
			return .init(statusCode: 206, body: data.subdata(in: start..<(end + 1)))
		}
	}

	@Test func secondArchiveOnTheSameExtractorPlansFromItsOwnDirectory() async throws {
		let extractor = extractor()
		let planet = try await extractor.makePlan(sourceURL: planetURL, sourceBuild: "planet", bounds: world, minZoom: 0, maxZoom: 0)
		#expect(planet.tileCount == 1)

		// With the cache keyed by offset alone this read the planet's root directory,
		// found no z1 tile, and threw `noTilesInArea`.
		let regional = try await extractor.makePlan(sourceURL: regionalURL, sourceBuild: "regional", bounds: world, minZoom: 1, maxZoom: 1)
		#expect(regional.tileCount == 1)
		#expect(regional.payloadBytes == 8)
	}

	@Test func secondArchiveExtractsItsOwnTiles() async throws {
		let extractor = extractor()
		_ = try await extractor.makePlan(sourceURL: planetURL, sourceBuild: "planet", bounds: world, minZoom: 0, maxZoom: 0)
		let plan = try await extractor.makePlan(sourceURL: regionalURL, sourceBuild: "regional", bounds: world, minZoom: 1, maxZoom: 1)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		defer { try? FileManager.default.removeItem(at: url) }
		try await extractor.extract(plan: plan, to: url)

		let written = try #require(PMTilesArchive(url: url))
		#expect(written.tileData(z: 1, x: 0, y: 0) == Data("regional".utf8))
		#expect(written.tileData(z: 0, x: 0, y: 0) == nil)
	}
}

private struct ArchiveTile {
	let z: UInt8
	let x: UInt32
	let y: UInt32
	let payload: Data
}

/// A complete single-directory PMTiles file with uncompressed payloads, laid out the way
/// `PMTilesExtractor.extract` writes one. `gap` filler bytes go between payloads; past the
/// extractor's coalescing gap, every tile becomes its own range request.
private func makeArchive(tiles: [ArchiveTile], minZoom: Int, maxZoom: Int, gap: Int = 0) -> Data {
	var tileData = Data()
	var entries: [PMTilesArchive.Entry] = []
	for (index, tile) in tiles.enumerated() {
		if index > 0, gap > 0 { tileData.append(Data(repeating: 0xAA, count: gap)) }
		let id = PMTilesArchive.zxyToTileID(z: tile.z, x: tile.x, y: tile.y)
		entries.append(.init(tileID: id, offset: UInt64(tileData.count), length: UInt32(tile.payload.count), runLength: 1))
		tileData.append(tile.payload)
	}
	entries.sort { $0.tileID < $1.tileID }
	let root = PMTilesExtractor.serializeDirectory(entries)
	let metadata = PMTilesExtractor.metadataJSON()
	let header = PMTilesExtractor.buildHeader(
		rootDirOffset: 127, rootDirLength: UInt64(root.count),
		metadataOffset: UInt64(127 + root.count), metadataLength: UInt64(metadata.count),
		tileDataOffset: UInt64(127 + root.count + metadata.count), tileDataLength: UInt64(tileData.count),
		numTiles: UInt64(entries.count),
		bounds: GeoBounds(minLon: -180, minLat: -85, maxLon: 180, maxLat: 85),
		minZoom: minZoom, maxZoom: maxZoom, tileType: .png, tileCompression: .none
	)
	return header + root + metadata + tileData
}

/// Serves one in-memory archive over the extractor's range seam, with knobs for the ways
/// a real host misbehaves: whole-file 200s, a replaced archive, a wrong Content-Range.
private final class FakeRangeServer: @unchecked Sendable {
	enum Mode {
		case partial
		case wholeFile
	}

	private let lock = NSLock()
	private var archive: Data
	private var etag: String?
	private var mode: Mode
	private struct Replacement {
		let after: Int
		let archive: Data
		let etag: String?
	}
	private var replacement: Replacement?
	private var rejectIfMatch = false
	private var contentRangeSkew: UInt64 = 0
	private var serveOnlyFirst: Int?
	private var log: [(range: ClosedRange<UInt64>, ifMatch: String?)] = []

	init(archive: Data, etag: String?, mode: Mode = .partial) {
		self.archive = archive
		self.etag = etag
		self.mode = mode
	}

	/// Swap in another archive once this many requests have been answered.
	func replace(with archive: Data, etag: String?, afterRequests count: Int) {
		lock.lock(); defer { lock.unlock() }
		replacement = Replacement(after: count, archive: archive, etag: etag)
	}

	/// Answer every If-Match request with 412, as a host whose file keeps changing would.
	func rejectAllIfMatch() {
		lock.lock(); defer { lock.unlock() }
		rejectIfMatch = true
	}

	/// Report Content-Range as starting this far past the requested offset.
	func skewContentRange(by amount: UInt64) {
		lock.lock(); defer { lock.unlock() }
		contentRangeSkew = amount
	}

	/// In whole-file mode, send only the first `count` bytes of the file.
	func truncateWholeFile(to count: Int) {
		lock.lock(); defer { lock.unlock() }
		serveOnlyFirst = count
	}

	var requests: [(range: ClosedRange<UInt64>, ifMatch: String?)] {
		lock.lock(); defer { lock.unlock() }
		return log
	}

	var headerFetches: Int { requests.filter { $0.ifMatch == nil }.count }

	var fetcher: PMTilesExtractor.RangeFetcher {
		{ [self] _, range, ifMatch in self.answer(range, ifMatch: ifMatch) }
	}

	private func answer(_ range: ClosedRange<UInt64>, ifMatch: String?) -> PMTilesExtractor.RangeResponse {
		lock.lock(); defer { lock.unlock() }
		if let replacement, log.count == replacement.after {
			archive = replacement.archive
			etag = replacement.etag
			self.replacement = nil
		}
		log.append((range, ifMatch))
		var headers: [String: String] = [:]
		if let etag { headers["ETag"] = etag }
		if let ifMatch, rejectIfMatch || ifMatch != etag {
			return .init(statusCode: 412, headers: headers, body: Data())
		}
		switch mode {
		case .wholeFile:
			let body = serveOnlyFirst.map { archive.prefix($0) } ?? archive
			return .init(statusCode: 200, headers: headers, body: Data(body))
		case .partial:
			let start = Int(range.lowerBound)
			guard start < archive.count else { return .init(statusCode: 416, headers: headers, body: Data()) }
			let end = min(Int(range.upperBound), archive.count - 1)
			headers["Content-Range"] = "bytes \(UInt64(start) + contentRangeSkew)-\(end)/\(archive.count)"
			return .init(statusCode: 206, headers: headers, body: archive.subdata(in: start..<(end + 1)))
		}
	}
}

@Suite("PMTilesExtractor range integrity")
struct PMTilesExtractorRangeIntegrityTests {

	private let world = GeoBounds(minLon: -180, minLat: -85, maxLon: 180, maxLat: 85)
	private let url = URL(fileURLWithPath: "/build.pmtiles")
	/// Past the extractor's 1 MiB coalescing gap, so the three tiles are three requests.
	private let gap = (1 << 20) + 1

	private var archiveA: Data {
		makeArchive(tiles: [
			ArchiveTile(z: 1, x: 0, y: 0, payload: Data("a-one".utf8)),
			ArchiveTile(z: 1, x: 1, y: 0, payload: Data("a-two-longer".utf8)),
			ArchiveTile(z: 1, x: 0, y: 1, payload: Data("a3".utf8))
		], minZoom: 1, maxZoom: 1, gap: gap)
	}

	/// Same tiles, different bytes and lengths: what the next day's build looks like.
	private var archiveB: Data {
		makeArchive(tiles: [
			ArchiveTile(z: 1, x: 0, y: 0, payload: Data("b-one-much-longer".utf8)),
			ArchiveTile(z: 1, x: 1, y: 0, payload: Data("b2".utf8)),
			ArchiveTile(z: 1, x: 0, y: 1, payload: Data("b-three".utf8))
		], minZoom: 1, maxZoom: 1, gap: gap)
	}

	private func extract(from server: FakeRangeServer) async throws -> (file: Data, plan: PMTilesExtractor.Plan) {
		let extractor = PMTilesExtractor(fetchRange: server.fetcher)
		let plan = try await extractor.makePlan(sourceURL: url, sourceBuild: "test", bounds: world, minZoom: 1, maxZoom: 1)
		let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		defer { try? FileManager.default.removeItem(at: destination) }
		let written = try await extractor.extract(plan: plan, to: destination)
		return (try Data(contentsOf: destination), written)
	}

	private func tiles(in file: Data) throws -> [Data?] {
		let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
		try file.write(to: destination)
		defer { try? FileManager.default.removeItem(at: destination) }
		let archive = try #require(PMTilesArchive(url: destination))
		return [archive.tileData(z: 1, x: 0, y: 0), archive.tileData(z: 1, x: 1, y: 0), archive.tileData(z: 1, x: 0, y: 1)]
	}

	@Test func partialResponsesCarryTheHeaderTagAsIfMatch() async throws {
		let server = FakeRangeServer(archive: archiveA, etag: "\"a-1\"")
		let result = try await extract(from: server)

		#expect(result.plan.sourceETag == "\"a-1\"")
		#expect(try tiles(in: result.file) == [Data("a-one".utf8), Data("a-two-longer".utf8), Data("a3".utf8)])
		let requests = server.requests
		#expect(requests.count == 4)   // header, then one request per tile
		#expect(requests.first?.ifMatch == nil)
		#expect(requests.dropFirst().allSatisfy { $0.ifMatch == "\"a-1\"" })
	}

	@Test func wholeFileResponsesAreSlicedToTheRange() async throws {
		let partial = try await extract(from: FakeRangeServer(archive: archiveA, etag: "\"a-1\""))
		let whole = try await extract(from: FakeRangeServer(archive: archiveA, etag: "\"a-1\"", mode: .wholeFile))

		#expect(whole.file == partial.file)
	}

	@Test func weakTagIsNeverSent() async throws {
		let server = FakeRangeServer(archive: archiveA, etag: "W/\"a-1\"")
		let result = try await extract(from: server)

		#expect(result.plan.sourceETag == nil)
		#expect(server.requests.allSatisfy { $0.ifMatch == nil })
	}

	@Test func replacedSourceIsPlannedAgainAndWrittenOver() async throws {
		let server = FakeRangeServer(archive: archiveA, etag: "\"a-1\"")
		// After the header and the first tile: the second tile's If-Match no longer holds.
		server.replace(with: archiveB, etag: "\"b-1\"", afterRequests: 2)
		let result = try await extract(from: server)

		let reference = try await extract(from: FakeRangeServer(archive: archiveB, etag: "\"b-1\""))
		#expect(result.file == reference.file)
		#expect(result.plan.sourceETag == "\"b-1\"")
		#expect(server.headerFetches == 2)
	}

	@Test func secondReplacementFails() async throws {
		let server = FakeRangeServer(archive: archiveA, etag: "\"a-1\"")
		let extractor = PMTilesExtractor(fetchRange: server.fetcher)
		let plan = try await extractor.makePlan(sourceURL: url, sourceBuild: "test", bounds: world, minZoom: 1, maxZoom: 1)
		server.rejectAllIfMatch()
		let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")

		await #expect(throws: PMTilesExtractorError.sourceReplaced) {
			try await extractor.extract(plan: plan, to: destination)
		}
		#expect(server.headerFetches == 2)   // one restart was attempted
		#expect(!FileManager.default.fileExists(atPath: destination.path))
	}

	@Test func contentRangeMismatchFails() async throws {
		let server = FakeRangeServer(archive: archiveA, etag: "\"a-1\"")
		server.skewContentRange(by: 1)
		let extractor = PMTilesExtractor(fetchRange: server.fetcher)

		await #expect(throws: PMTilesExtractorError.rangeMismatch) {
			try await extractor.makePlan(sourceURL: url, sourceBuild: "test", bounds: world, minZoom: 1, maxZoom: 1)
		}
	}

	@Test func wholeFileShorterThanTheRangeStartFails() async throws {
		// Header and directory fit in the first 200 bytes; every tile sits past them.
		let server = FakeRangeServer(archive: archiveA, etag: "\"a-1\"", mode: .wholeFile)
		server.truncateWholeFile(to: 200)
		let extractor = PMTilesExtractor(fetchRange: server.fetcher)
		let plan = try await extractor.makePlan(sourceURL: url, sourceBuild: "test", bounds: world, minZoom: 1, maxZoom: 1)
		let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")

		await #expect(throws: PMTilesExtractorError.rangeMismatch) {
			try await extractor.extract(plan: plan, to: destination)
		}
		#expect(!FileManager.default.fileExists(atPath: destination.path))
	}

	@Test func contentRangeParsing() {
		#expect(PMTilesExtractor.parseContentRange("bytes 0-16383/139202898553")! == (0, 16383))
		#expect(PMTilesExtractor.parseContentRange("bytes 512-1023/*")! == (512, 1023))
		#expect(PMTilesExtractor.parseContentRange("bytes */1024") == nil)
		#expect(PMTilesExtractor.parseContentRange("items 0-1/2") == nil)
		#expect(PMTilesExtractor.parseContentRange("bytes 9-3/10") == nil)
	}

	@Test func strongTagsOnly() {
		#expect(PMTilesExtractor.strongETag("\"abc-519\"") == "\"abc-519\"")
		#expect(PMTilesExtractor.strongETag(" \"abc\" ") == "\"abc\"")
		#expect(PMTilesExtractor.strongETag("W/\"abc\"") == nil)
		#expect(PMTilesExtractor.strongETag("") == nil)
		#expect(PMTilesExtractor.strongETag(nil) == nil)
	}
}
