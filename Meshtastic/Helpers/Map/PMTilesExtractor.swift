//
//  PMTilesExtractor.swift
//  Meshtastic
//
//  Extracts a bounding-box subset of a remote PMTiles v3 archive (the public
//  Protomaps daily build) into a small local `.pmtiles` file, using HTTP range
//  requests — never downloading the whole planet.
//
//  Strategy:
//    1. Range-fetch the source header + root directory, keeping the archive's strong
//       ETag. Every later range request carries it as If-Match, so an archive the host
//       replaces mid-download is noticed and re-planned instead of copied half-and-half.
//    2. Enumerate the slippy-map tiles covering the bounds across the zoom range
//       and walk the source directory tree (fetching leaf directories on demand)
//       to resolve each tile's byte range. This alone yields an exact size
//       estimate without downloading any tile payloads.
//    3. Coalesce adjacent tile byte ranges into batched range requests, copy the
//       (already gzip-compressed MVT) payloads verbatim, and stream them to disk.
//    4. Write a valid PMTiles v3 file with a single uncompressed root directory
//       (fine for a memory-mapped local read) and the tile payloads.
//
//  Reuses the exact header / directory / gzip / Hilbert-id logic from
//  `PMTilesArchive` so the reader and extractor never diverge.
//

import Foundation
import OSLog

enum PMTilesExtractorError: Error, LocalizedError, Equatable {
	case noBuildAvailable
	case badHeader
	case rangeRequestFailed(Int)
	/// The host replaced the archive while it was being read (412, 416, or a 206 with
	/// a different strong ETag), twice in one extract.
	case sourceReplaced
	/// A range response that doesn't cover the bytes asked for: wrong Content-Range
	/// start, a short body, or a whole-file reply shorter than the range start.
	case rangeMismatch
	case areaTooLarge(Int)
	case noTilesInArea
	case writeFailed
	case cancelled

	var errorDescription: String? {
		switch self {
		case .noBuildAvailable: return "No recent Protomaps map build could be reached."
		case .badHeader: return "The map source returned an unexpected format."
		case .rangeRequestFailed(let code): return "The map source rejected a range request (HTTP \(code))."
		case .sourceReplaced: return "The map source changed while downloading. Try again."
		case .rangeMismatch: return "The map source returned the wrong bytes for a range request."
		case .areaTooLarge(let tiles): return "That area is too large to download (\(tiles) tiles). Zoom in or lower the detail level."
		case .noTilesInArea: return "There is no map coverage for that area."
		case .writeFailed: return "The downloaded map could not be saved."
		case .cancelled: return "The download was cancelled."
		}
	}
}

/// Extracts a region of the Protomaps basemap into a local `.pmtiles` archive.
final class PMTilesExtractor {

	/// Hard ceiling on tiles per region — guards against an unbounded area selection.
	static let maxTiles = 600_000
	/// Coalesce source byte ranges separated by gaps no larger than this into one request.
	private static let maxCoalesceGap: UInt64 = 1 << 20            // 1 MiB
	/// Cap a single coalesced range request's span to bound peak memory.
	private static let maxCoalesceSpan: UInt64 = 24 << 20          // 24 MiB

	/// Result of resolving which source tiles a region needs (no payloads fetched yet).
	struct Plan {
		let sourceURL: URL
		let sourceBuild: String
		/// The archive's strong ETag at planning time, sent as If-Match on every later
		/// range request. Nil when the host sends none (or only a weak one): then a
		/// replaced archive can't be told apart and the copy is unverified.
		let sourceETag: String?
		/// The archive's Last-Modified at planning time, when the host sent one.
		let sourceLastModified: Date?
		let header: PMTilesHeader
		/// The extracted region's geometry and effective zoom range (clamped to the source).
		let bounds: GeoBounds
		let minZoom: Int
		let maxZoom: Int
		/// Unique source payloads to copy, keyed by absolute source offset → length.
		fileprivate let blobs: [Blob]
		/// Output directory entries (tileID → output offset), sorted by tileID.
		fileprivate let entries: [PMTilesArchive.Entry]

		var tileCount: Int { entries.count }
		var payloadBytes: Int64 { blobs.reduce(0) { $0 + Int64($1.length) } }
	}

	fileprivate struct Blob {
		let sourceOffset: UInt64
		let length: UInt32
		let outputOffset: UInt64
	}

	/// One answer to a range request: status, headers and bytes. The extractor needs
	/// nothing else from the transport.
	struct RangeResponse {
		let statusCode: Int
		let headers: [String: String]
		let body: Data

		init(statusCode: Int, headers: [String: String] = [:], body: Data) {
			self.statusCode = statusCode
			self.headers = headers
			self.body = body
		}

		/// A header by name, case-insensitively.
		func header(_ name: String) -> String? {
			headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
		}
	}

	/// Fetches one byte range of a remote archive, sending `ifMatch` as If-Match when
	/// given. The default goes through `URLSession`; tests hand in a closure that serves
	/// archives from memory.
	typealias RangeFetcher = @Sendable (URL, ClosedRange<UInt64>, _ ifMatch: String?) async throws -> RangeResponse

	/// An archive being read: where it is and the validator its plan was made with.
	private struct Source {
		let url: URL
		let etag: String?
	}

	private let fetch: RangeFetcher
	/// Decoded directories, keyed by archive, version AND offset. One extractor plans the
	/// global terrain archive and then a regional one, and every PMTiles file keeps its
	/// root directory at offset 127, so an offset-only key handed the second plan the first
	/// archive's directory. The ETag keeps a replaced archive from reusing the old one's.
	private struct DirectoryKey: Hashable {
		let url: URL
		let etag: String?
		let offset: UInt64
	}
	private var leafCache: [DirectoryKey: [PMTilesArchive.Entry]] = [:]

	/// The extraction time written into each archive's metadata. Injectable so tests
	/// can compare two extracts byte for byte.
	private let now: @Sendable () -> Date

	init(session: URLSession = .shared) {
		fetch = Self.rangeFetcher(session: session)
		now = { .now }
	}

	init(fetchRange: @escaping RangeFetcher, now: @escaping @Sendable () -> Date = { .now }) {
		fetch = fetchRange
		self.now = now
	}

	// MARK: - Build resolution

	/// Probes backward from `today` for the most recent daily build that exists and
	/// supports range requests. Builds are retained for roughly two weeks.
	func latestBuild(today: Date = .now, lookbackDays: Int = 16) async -> (url: URL, build: String)? {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.dateFormat = "yyyyMMdd"

		for offset in 0..<lookbackDays {
			guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
			let build = formatter.string(from: day)
			guard let url = URL(string: "https://build.protomaps.com/\(build).pmtiles") else { continue }
			if await archiveExists(url) {
				Logger.services.info("🗺️ [Offline] Using Protomaps build \(build, privacy: .public)")
				return (url, build)
			}
		}
		return nil
	}

	/// Whether a PMTiles archive exists at `url`, probing the 7-byte magic with a range request.
	func archiveExists(_ url: URL) async -> Bool {
		do {
			let data = try await fetchRange(url, start: 0, end: 6, ifMatch: nil).body
			return data.count == 7 && data == Data("PMTiles".utf8)
		} catch {
			return false
		}
	}

	// MARK: - Planning (resolve tiles + exact size, no payload download)

	/// Resolves the tiles a region needs. If the archive is replaced between the header
	/// fetch and a directory fetch, planning starts over once from a fresh header.
	func makePlan(sourceURL: URL, sourceBuild: String, bounds: GeoBounds, minZoom: Int, maxZoom: Int) async throws -> Plan {
		do {
			return try await resolvePlan(sourceURL: sourceURL, sourceBuild: sourceBuild, bounds: bounds, minZoom: minZoom, maxZoom: maxZoom)
		} catch PMTilesExtractorError.sourceReplaced {
			Logger.services.info("🗺️ [Offline] Source archive replaced while planning; planning again")
			forgetDirectories(of: sourceURL)
			return try await resolvePlan(sourceURL: sourceURL, sourceBuild: sourceBuild, bounds: bounds, minZoom: minZoom, maxZoom: maxZoom)
		}
	}

	private func resolvePlan(sourceURL: URL, sourceBuild: String, bounds: GeoBounds, minZoom: Int, maxZoom: Int) async throws -> Plan {
		// Header + root directory live at the start of the file; one fetch usually covers both.
		let head = try await fetchRange(sourceURL, start: 0, end: 16_383, ifMatch: nil)
		guard let header = PMTilesArchive.parseHeader(head.body) else { throw PMTilesExtractorError.badHeader }
		let source = Source(url: sourceURL, etag: head.etag)

		let rootEntries = try await directory(
			at: header.rootDirOffset,
			length: header.rootDirLength,
			compression: header.internalCompression,
			source: source,
			prefetched: head.body
		)

		let lo = max(minZoom, Int(header.minZoom))
		let hi = min(maxZoom, Int(header.maxZoom))
		guard lo <= hi else { throw PMTilesExtractorError.noTilesInArea }

		let tileIDs = Self.tileIDs(in: bounds, minZoom: lo, maxZoom: hi)
		guard !tileIDs.isEmpty else { throw PMTilesExtractorError.noTilesInArea }
		guard tileIDs.count <= Self.maxTiles else { throw PMTilesExtractorError.areaTooLarge(tileIDs.count) }

		// Resolve each tile to a source byte range, deduplicating shared payloads (runs).
		var resolved: [(tileID: UInt64, source: UInt64, length: UInt32)] = []
		resolved.reserveCapacity(tileIDs.count)
		for tileID in tileIDs {
			try Task.checkCancellation()
			if let range = try await resolve(tileID: tileID, header: header, root: rootEntries, source: source) {
				resolved.append((tileID, range.source, range.length))
			}
		}
		guard !resolved.isEmpty else { throw PMTilesExtractorError.noTilesInArea }

		// Build the unique payload list (sorted by source offset) and assign output offsets.
		let uniqueSources = Set(resolved.map { $0.source })
		let lengthBySource = Dictionary(resolved.map { ($0.source, $0.length) }, uniquingKeysWith: { lhs, _ in lhs })
		var blobs: [Blob] = []
		var outputBySource: [UInt64: UInt64] = [:]
		var cursor: UInt64 = 0
		for source in uniqueSources.sorted() {
			let length = lengthBySource[source] ?? 0
			blobs.append(Blob(sourceOffset: source, length: length, outputOffset: cursor))
			outputBySource[source] = cursor
			cursor += UInt64(length)
		}

		let entries = resolved
			.map { PMTilesArchive.Entry(tileID: $0.tileID, offset: outputBySource[$0.source] ?? 0, length: $0.length, runLength: 1) }
			.sorted { $0.tileID < $1.tileID }

		return Plan(sourceURL: sourceURL, sourceBuild: sourceBuild, sourceETag: source.etag, sourceLastModified: head.lastModified, header: header, bounds: bounds, minZoom: lo, maxZoom: hi, blobs: blobs, entries: entries)
	}

	/// Convenience: resolve the latest build and return the exact download size for a region.
	func estimate(bounds: GeoBounds, minZoom: Int, maxZoom: Int) async throws -> (tileCount: Int, bytes: Int64, build: String) {
		guard let build = await latestBuild() else { throw PMTilesExtractorError.noBuildAvailable }
		let plan = try await makePlan(sourceURL: build.url, sourceBuild: build.build, bounds: bounds, minZoom: minZoom, maxZoom: maxZoom)
		return (plan.tileCount, plan.payloadBytes + Int64(estimatedOverhead(plan)), build.build)
	}

	// MARK: - Extraction (download payloads + write file)

	/// Downloads the planned tiles and writes a complete `.pmtiles` file to `destination`.
	/// `onProgress` is invoked with (bytesWritten, totalBytes) on an arbitrary queue.
	///
	/// If the host replaces the archive while this runs (a range request comes back 412,
	/// 416, or with a different strong ETag), the region is planned again from a fresh
	/// header and the file is written over from the start, once. A second replacement
	/// fails with `sourceReplaced`. Returns the plan that was written, which is the
	/// fresh one after a restart.
	@discardableResult
	func extract(plan: Plan, to destination: URL, onProgress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> Plan {
		FileManager.default.createFile(atPath: destination.path, contents: nil)
		guard let handle = try? FileHandle(forWritingTo: destination) else { throw PMTilesExtractorError.writeFailed }
		defer { try? handle.close() }

		do {
			do {
				try await write(plan: plan, to: handle, onProgress: onProgress)
				return plan
			} catch PMTilesExtractorError.sourceReplaced {
				Logger.services.info("🗺️ [Offline] Source archive replaced mid-extract; planning again")
				forgetDirectories(of: plan.sourceURL)
				let fresh = try await resolvePlan(
					sourceURL: plan.sourceURL, sourceBuild: plan.sourceBuild,
					bounds: plan.bounds, minZoom: plan.minZoom, maxZoom: plan.maxZoom
				)
				try handle.truncate(atOffset: 0)
				try handle.seek(toOffset: 0)
				try await write(plan: fresh, to: handle, onProgress: onProgress)
				return fresh
			}
		} catch is CancellationError {
			try? FileManager.default.removeItem(at: destination)
			throw PMTilesExtractorError.cancelled
		} catch let error as PMTilesExtractorError {
			try? FileManager.default.removeItem(at: destination)
			throw error
		} catch {
			try? FileManager.default.removeItem(at: destination)
			Logger.services.error("🗺️ [Offline] Extract write failed: \(error.localizedDescription, privacy: .public)")
			throw PMTilesExtractorError.writeFailed
		}
	}

	/// Writes one plan's header, directory, metadata and tile payloads to an open file.
	private func write(plan: Plan, to handle: FileHandle, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws {
		let rootDir = Self.serializeDirectory(plan.entries)
		let metadata = Self.metadataJSON(sourceBuild: plan.sourceBuild, sourceETag: plan.sourceETag, extractedAt: now())
		let tileDataOffset = UInt64(127 + rootDir.count + metadata.count)
		let tileDataLength = plan.blobs.reduce(UInt64(0)) { $0 + UInt64($1.length) }

		let header = Self.buildHeader(
			rootDirOffset: 127,
			rootDirLength: UInt64(rootDir.count),
			metadataOffset: UInt64(127 + rootDir.count),
			metadataLength: UInt64(metadata.count),
			tileDataOffset: tileDataOffset,
			tileDataLength: tileDataLength,
			numTiles: UInt64(plan.entries.count),
			bounds: plan.bounds,
			minZoom: plan.minZoom,
			maxZoom: plan.maxZoom,
			tileType: plan.header.tileType,
			tileCompression: plan.header.tileCompression
		)

		try handle.write(contentsOf: header)
		try handle.write(contentsOf: rootDir)
		try handle.write(contentsOf: metadata)

		do {
			let total = Int64(tileDataLength)
			var written: Int64 = 0
			onProgress?(0, total)

			// Write blobs in ascending output-offset order (== ascending source order),
			// fetching coalesced source spans to limit the number of HTTP requests.
			let ordered = plan.blobs.sorted { $0.outputOffset < $1.outputOffset }
			var index = 0
			while index < ordered.count {
				try Task.checkCancellation()
				let spanStart = ordered[index].sourceOffset
				var spanEnd = spanStart + UInt64(ordered[index].length)
				var last = index
				while last + 1 < ordered.count {
					let next = ordered[last + 1]
					let gap = next.sourceOffset - spanEnd
					let span = next.sourceOffset + UInt64(next.length) - spanStart
					if gap <= Self.maxCoalesceGap && span <= Self.maxCoalesceSpan {
						spanEnd = next.sourceOffset + UInt64(next.length)
						last += 1
					} else { break }
				}

				let chunk = try await fetchRange(plan.sourceURL, start: spanStart, end: spanEnd - 1, ifMatch: plan.sourceETag).body
				for blob in ordered[index...last] {
					let lower = Int(blob.sourceOffset - spanStart)
					let upper = lower + Int(blob.length)
					guard upper <= chunk.count else { throw PMTilesExtractorError.rangeMismatch }
					try handle.write(contentsOf: chunk.subdata(in: lower..<upper))
					written += Int64(blob.length)
				}
				onProgress?(written, total)
				index = last + 1
			}
		}
	}

	// MARK: - Directory traversal

	private func resolve(tileID: UInt64, header: PMTilesHeader, root: [PMTilesArchive.Entry], source: Source) async throws -> (source: UInt64, length: UInt32)? {
		var dirOffset = header.rootDirOffset
		var dirLength = header.rootDirLength
		var entries = root
		for depth in 0..<4 {
			if depth > 0 {
				entries = try await directory(at: dirOffset, length: dirLength, compression: header.internalCompression, source: source, prefetched: nil)
			}
			guard let entry = PMTilesArchive.find(tileID, in: entries) else { return nil }
			if entry.runLength == 0 {
				// Overflow-safe offset math, matching the #2192 hardening of PMTilesArchive.
				let (leaf, overflow) = header.leafDirOffset.addingReportingOverflow(entry.offset)
				guard !overflow else { return nil }
				dirOffset = leaf
				dirLength = UInt64(entry.length)
			} else {
				let (tileOffset, overflow) = header.tileDataOffset.addingReportingOverflow(entry.offset)
				guard !overflow else { return nil }
				return (tileOffset, entry.length)
			}
		}
		return nil
	}

	private func directory(at offset: UInt64, length: UInt64, compression: PMTilesCompression, source: Source, prefetched: Data?) async throws -> [PMTilesArchive.Entry] {
		let key = DirectoryKey(url: source.url, etag: source.etag, offset: offset)
		if let cached = leafCache[key] { return cached }
		let raw: Data
		// Overflow-safe range math (matches #2192): guard the add and the Int conversions so a
		// crafted header/directory offset can't trap while planning an extraction.
		let (end, addOverflow) = offset.addingReportingOverflow(length)
		if let prefetched, !addOverflow, end <= UInt64(prefetched.count),
		   let start = Int(exactly: offset), let stop = Int(exactly: end) {
			raw = prefetched.subdata(in: start..<stop)
		} else if length > 0, !addOverflow {
			raw = try await fetchRange(source.url, start: offset, end: end - 1, ifMatch: source.etag).body
		} else {
			return []
		}
		// A whole-file reply that ends inside the directory would parse as an empty one.
		guard UInt64(raw.count) == length else { throw PMTilesExtractorError.rangeMismatch }
		let decompressed = compression == .gzip ? (PMTilesArchive.gunzip(raw) ?? raw) : raw
		let entries = PMTilesArchive.deserializeDirectory(decompressed)
		leafCache[key] = entries
		return entries
	}

	/// Drops the cached directories of one archive, after the host replaced it.
	private func forgetDirectories(of url: URL) {
		leafCache = leafCache.filter { $0.key.url != url }
	}

	// MARK: - Tile enumeration

	/// PMTiles Hilbert tile-ids for every slippy tile covering `bounds` over the zoom range.
	static func tileIDs(in bounds: GeoBounds, minZoom: Int, maxZoom: Int) -> [UInt64] {
		var ids: [UInt64] = []
		for z in minZoom...maxZoom {
			let n = UInt32(1) << UInt32(z)
			let maxIndex = n - 1
			let (x0, y0) = tileXY(lon: bounds.minLon, lat: bounds.maxLat, z: z) // top-left
			let (x1, y1) = tileXY(lon: bounds.maxLon, lat: bounds.minLat, z: z) // bottom-right
			let xLo = min(x0, x1), xHi = min(max(x0, x1), maxIndex)
			let yLo = min(y0, y1), yHi = min(max(y0, y1), maxIndex)
			guard xLo <= maxIndex, yLo <= maxIndex else { continue }
			for x in xLo...xHi {
				for y in yLo...yHi {
					ids.append(PMTilesArchive.zxyToTileID(z: UInt8(z), x: x, y: y))
				}
			}
		}
		return ids
	}

	/// Number of slippy tiles covering `bounds` over the zoom range, without allocating ids.
	/// Cheap enough to call live as a selection box is dragged.
	static func tileCount(in bounds: GeoBounds, minZoom: Int, maxZoom: Int) -> Int {
		guard minZoom <= maxZoom else { return 0 }
		var count = 0
		for z in minZoom...maxZoom {
			let maxIndex = (UInt32(1) << UInt32(z)) - 1
			let (x0, y0) = tileXY(lon: bounds.minLon, lat: bounds.maxLat, z: z)
			let (x1, y1) = tileXY(lon: bounds.maxLon, lat: bounds.minLat, z: z)
			let xSpan = Int(min(max(x0, x1), maxIndex)) - Int(min(x0, x1)) + 1
			let ySpan = Int(min(max(y0, y1), maxIndex)) - Int(min(y0, y1)) + 1
			count += max(0, xSpan) * max(0, ySpan)
		}
		return count
	}

	/// A network-free size estimate for the UI. Real size is known only after planning —
	/// this only needs to be in the ballpark while the exact plan computes. Per-tile
	/// averages were measured against a real build for an urban region: high-zoom tiles
	/// are much smaller than mid-zoom ones (a flat constant overstated High detail by
	/// ~70%). Rural areas run far below these numbers, which is why the UI marks this
	/// value as approximate until the exact plan replaces it.
	static func roughByteEstimate(in bounds: GeoBounds, minZoom: Int, maxZoom: Int) -> Int64 {
		guard minZoom <= maxZoom else { return 0 }
		func perTileBytes(_ z: Int) -> Int64 {
			switch z {
			case ..<13: return 40_960
			case 13: return 34_816
			case 14: return 20_480
			default: return 13_824
			}
		}
		var total: Int64 = 0
		for z in minZoom...maxZoom {
			total += Int64(tileCount(in: bounds, minZoom: z, maxZoom: z)) * perTileBytes(z)
		}
		return total
	}

	/// Web-Mercator slippy tile coordinate for a lon/lat at zoom `z` (clamped to valid range).
	static func tileXY(lon: Double, lat: Double, z: Int) -> (x: UInt32, y: UInt32) {
		let n = Double(UInt32(1) << UInt32(z))
		let clampedLat = min(max(lat, -85.05112878), 85.05112878)
		let latRad = clampedLat * .pi / 180
		let xf = (lon + 180) / 360 * n
		let yf = (1 - asinh(tan(latRad)) / .pi) / 2 * n
		let x = UInt32(min(max(xf, 0), n - 1))
		let y = UInt32(min(max(yf, 0), n - 1))
		return (x, y)
	}

	// MARK: - PMTiles v3 writing

	/// Serializes directory entries into the PMTiles v3 directory encoding. Offsets are
	/// always written as `offset + 1` (never using the contiguous-run shortcut), so a
	/// reader reconstructs them exactly.
	static func serializeDirectory(_ entries: [PMTilesArchive.Entry]) -> Data {
		var out = [UInt8]()
		func putVarint(_ value: UInt64) {
			var x = value
			while x >= 0x80 { out.append(UInt8(x & 0x7F) | 0x80); x >>= 7 }
			out.append(UInt8(x))
		}
		putVarint(UInt64(entries.count))
		var lastID: UInt64 = 0
		for entry in entries { putVarint(entry.tileID - lastID); lastID = entry.tileID }
		for entry in entries { putVarint(UInt64(entry.runLength)) }
		for entry in entries { putVarint(UInt64(entry.length)) }
		for entry in entries { putVarint(entry.offset + 1) }
		return Data(out)
	}

	private func estimatedOverhead(_ plan: Plan) -> Int {
		Self.serializeDirectory(plan.entries).count
			+ Self.metadataJSON(sourceBuild: plan.sourceBuild, sourceETag: plan.sourceETag, extractedAt: now()).count + 127
	}

	// swiftlint:disable:next function_parameter_count
	static func buildHeader(
		rootDirOffset: UInt64, rootDirLength: UInt64,
		metadataOffset: UInt64, metadataLength: UInt64,
		tileDataOffset: UInt64, tileDataLength: UInt64,
		numTiles: UInt64, bounds: GeoBounds, minZoom: Int, maxZoom: Int,
		tileType: PMTilesTileType, tileCompression: PMTilesCompression
	) -> Data {
		var bytes = [UInt8](repeating: 0, count: 127)
		let magic = [UInt8]("PMTiles".utf8)
		bytes.replaceSubrange(0..<7, with: magic)
		bytes[7] = 3

		func putU64(_ value: UInt64, at offset: Int) {
			var little = value.littleEndian
			withUnsafeBytes(of: &little) { raw in
				for i in 0..<8 { bytes[offset + i] = raw[i] }
			}
		}
		func putI32(_ value: Int32, at offset: Int) {
			var little = value.littleEndian
			withUnsafeBytes(of: &little) { raw in
				for i in 0..<4 { bytes[offset + i] = raw[i] }
			}
		}

		putU64(rootDirOffset, at: 8)
		putU64(rootDirLength, at: 16)
		putU64(metadataOffset, at: 24)
		putU64(metadataLength, at: 32)
		// No leaf directories: point the leaf section at the tile data with zero length.
		putU64(tileDataOffset, at: 40)
		putU64(0, at: 48)
		putU64(tileDataOffset, at: 56)
		putU64(tileDataLength, at: 64)
		putU64(numTiles, at: 72)   // addressed tiles
		putU64(numTiles, at: 80)   // tile entries
		putU64(numTiles, at: 88)   // tile contents (upper bound)

		bytes[96] = 0                                   // not clustered: tile data is written in source-offset order
		bytes[97] = PMTilesCompression.none.rawValue    // internal (directories/metadata) uncompressed
		bytes[98] = tileCompression.rawValue            // tile payloads copied verbatim
		bytes[99] = tileType.rawValue
		bytes[100] = UInt8(clamping: minZoom)
		bytes[101] = UInt8(clamping: maxZoom)
		putI32(Int32((bounds.minLon * 1e7).rounded()), at: 102)
		putI32(Int32((bounds.minLat * 1e7).rounded()), at: 106)
		putI32(Int32((bounds.maxLon * 1e7).rounded()), at: 110)
		putI32(Int32((bounds.maxLat * 1e7).rounded()), at: 114)
		bytes[118] = UInt8(clamping: minZoom)
		putI32(Int32(((bounds.minLon + bounds.maxLon) / 2 * 1e7).rounded()), at: 119)
		putI32(Int32(((bounds.minLat + bounds.maxLat) / 2 * 1e7).rounded()), at: 123)
		return Data(bytes)
	}
}

// MARK: - HTTP range fetch

extension PMTilesExtractor {

	/// The bytes of one range plus the archive's strong ETag and Last-Modified, if sent.
	private struct Chunk {
		let body: Data
		let etag: String?
		var lastModified: Date?
	}

	/// The archive's current strong ETag, from one 16 KiB range fetch, or nil when the
	/// host sends none. What a staleness check compares a download's stored tag with.
	func currentETag(of url: URL) async throws -> String? {
		try await fetchRange(url, start: 0, end: 16_383, ifMatch: nil).etag
	}

	/// An HTTP-date (`Fri, 11 Sep 2026 14:58:22 GMT`).
	static func parseHTTPDate(_ value: String?) -> Date? {
		guard let value else { return nil }
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "GMT")
		formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
		return formatter.date(from: value)
	}

	/// One validated range. 412 and 416, or a 206 whose strong ETag differs from
	/// `ifMatch`, mean the archive was replaced. A 206 must carry a Content-Range that
	/// starts where asked, and as many bytes as it says. A 200 means the Range header was
	/// ignored and the whole file came back; the range is cut out of it, and a body
	/// that ends before the range starts is an error.
	private func fetchRange(_ url: URL, start: UInt64, end: UInt64, ifMatch: String?) async throws -> Chunk {
		let response = try await fetch(url, start...end, ifMatch)
		switch response.statusCode {
		case 412, 416:
			throw PMTilesExtractorError.sourceReplaced
		case 200, 206:
			break
		default:
			Logger.services.error("🗺️ [Offline] Range \(start, privacy: .public)-\(end, privacy: .public) of \(url.absoluteString, privacy: .public) failed: HTTP \(response.statusCode, privacy: .public)")
			throw PMTilesExtractorError.rangeRequestFailed(response.statusCode)
		}
		let etag = Self.strongETag(response.header("ETag"))
		if let ifMatch, let etag, etag != ifMatch {
			throw PMTilesExtractorError.sourceReplaced
		}
		let body = response.body
		let base = body.startIndex
		let wanted = Int(end - start + 1)

		if response.statusCode == 200 {
			guard let first = Int(exactly: start), first < body.count else { throw PMTilesExtractorError.rangeMismatch }
			let last = min(first + wanted, body.count)
			return Chunk(body: Data(body[(base + first)..<(base + last)]), etag: etag, lastModified: Self.parseHTTPDate(response.header("Last-Modified")))
		}
		// The header can claim the whole UInt64 span; the add must not trap.
		guard let contentRange = response.header("Content-Range"),
			  let parsed = Self.parseContentRange(contentRange), parsed.start == start,
			  case let (length, overflow) = (parsed.end - parsed.start).addingReportingOverflow(1),
			  !overflow, UInt64(body.count) == length else {
			throw PMTilesExtractorError.rangeMismatch
		}
		return Chunk(body: body.count > wanted ? Data(body[base..<(base + wanted)]) : body, etag: etag, lastModified: Self.parseHTTPDate(response.header("Last-Modified")))
	}

	/// A validator worth sending: non-empty and strong. A weak tag (`W/"…"`) says the
	/// bytes may differ between two responses, which is exactly what a range copy can't
	/// tolerate, so it is treated as no tag at all.
	static func strongETag(_ value: String?) -> String? {
		guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty, !value.hasPrefix("W/") else { return nil }
		return value
	}

	/// The `start-end` of a `Content-Range: bytes start-end/total` header.
	static func parseContentRange(_ value: String) -> (start: UInt64, end: UInt64)? {
		let trimmed = value.trimmingCharacters(in: .whitespaces)
		guard trimmed.lowercased().hasPrefix("bytes ") else { return nil }
		let spec = trimmed.dropFirst(6)
		guard let slash = spec.firstIndex(of: "/") else { return nil }
		let range = spec[..<slash]
		guard let dash = range.firstIndex(of: "-"),
			  let start = UInt64(range[..<dash]),
			  let end = UInt64(range[range.index(after: dash)...]),
			  end >= start else { return nil }
		return (start, end)
	}

	/// The production fetcher: one `Range` request per call, bypassing the URL cache. A host
	/// that ignores the range answers 200 with the whole file; the transfer is cancelled once
	/// it passes the end of the range, so a 16 KiB check of a multi-gigabyte archive never
	/// buffers the archive.
	static func rangeFetcher(session: URLSession) -> RangeFetcher {
		{ url, range, ifMatch in
			var request = URLRequest(url: url)
			request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
			if let ifMatch { request.setValue(ifMatch, forHTTPHeaderField: "If-Match") }
			request.cachePolicy = .reloadIgnoringLocalCacheData
			// A 200 holds the file from byte 0, so the range ends `upperBound + 1` bytes in.
			let loader = BoundedRangeLoader(wholeFileLimit: Int(clamping: range.upperBound) &+ 1)
			let (data, http) = try await loader.load(request, in: session)
			var headers: [String: String] = [:]
			for (name, value) in http.allHeaderFields {
				if let name = name as? String, let value = value as? String { headers[name] = value }
			}
			return RangeResponse(statusCode: http.statusCode, headers: headers, body: data)
		}
	}
}

/// One range request read in chunks as they arrive. A 200 is cut off once it holds
/// `wholeFileLimit` bytes; any other status is read to the end.
private final class BoundedRangeLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
	private let wholeFileLimit: Int
	private let lock = NSLock()
	private var body = Data()
	private var response: HTTPURLResponse?
	private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?

	init(wholeFileLimit: Int) {
		self.wholeFileLimit = wholeFileLimit
	}

	func load(_ request: URLRequest, in session: URLSession) async throws -> (Data, HTTPURLResponse) {
		let task = session.dataTask(with: request)
		task.delegate = self
		return try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				lock.withLock { self.continuation = continuation }
				task.resume()
			}
		} onCancel: {
			task.cancel()
		}
	}

	private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
		let continuation = lock.withLock {
			defer { self.continuation = nil }
			return self.continuation
		}
		continuation?.resume(with: result)
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
		guard let http = response as? HTTPURLResponse else {
			finish(.failure(PMTilesExtractorError.rangeRequestFailed(-1)))
			return .cancel
		}
		lock.withLock { self.response = http }
		return .allow
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		let done: (Data, HTTPURLResponse)? = lock.withLock {
			body.append(data)
			guard let response, response.statusCode == 200, body.count >= wholeFileLimit else { return nil }
			return (body, response)
		}
		if let done {
			dataTask.cancel()
			finish(.success(done))
		}
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		let (body, response) = lock.withLock { (self.body, self.response) }
		if let error {
			finish(.failure(error))
		} else if let response {
			finish(.success((body, response)))
		} else {
			finish(.failure(PMTilesExtractorError.rangeRequestFailed(-1)))
		}
	}
}

// MARK: - Metadata

extension PMTilesExtractor {

	/// Keys this app adds to an extracted archive's metadata, next to the attribution.
	enum MetadataKey {
		static let sourceBuild = "meshtastic:source_build"
		static let sourceETag = "meshtastic:source_etag"
		static let extractedAt = "meshtastic:extracted_at"
	}

	/// The archive's metadata JSON: the attribution and name, plus where and when the
	/// tiles came from. Keys are sorted so the same inputs give the same bytes.
	static func metadataJSON(sourceBuild: String? = nil, sourceETag: String? = nil, extractedAt: Date? = nil) -> Data {
		var json = ["attribution": "© OpenStreetMap, Protomaps", "name": "Meshtastic offline region"]
		json[MetadataKey.sourceBuild] = sourceBuild
		json[MetadataKey.sourceETag] = sourceETag
		json[MetadataKey.extractedAt] = extractedAt.map { ISO8601DateFormatter().string(from: $0) }
		return (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
	}
}
