//
//  PMTilesExtractor.swift
//  Meshtastic
//
//  Extracts a bounding-box subset of a remote PMTiles v3 archive (the public
//  Protomaps daily build) into a small local `.pmtiles` file, using HTTP range
//  requests — never downloading the whole planet.
//
//  Strategy:
//    1. Range-fetch the source header + root directory.
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

enum PMTilesExtractorError: Error, LocalizedError {
	case noBuildAvailable
	case badHeader
	case rangeRequestFailed(Int)
	case areaTooLarge(Int)
	case noTilesInArea
	case writeFailed
	case cancelled

	var errorDescription: String? {
		switch self {
		case .noBuildAvailable: return "No recent Protomaps map build could be reached."
		case .badHeader: return "The map source returned an unexpected format."
		case .rangeRequestFailed(let code): return "The map source rejected a range request (HTTP \(code))."
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

	private let session: URLSession
	private var leafCache: [UInt64: [PMTilesArchive.Entry]] = [:]

	init(session: URLSession = .shared) {
		self.session = session
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
			if await buildExists(url) {
				Logger.services.info("🗺️ [Offline] Using Protomaps build \(build, privacy: .public)")
				return (url, build)
			}
		}
		return nil
	}

	private func buildExists(_ url: URL) async -> Bool {
		do {
			let data = try await fetchRange(url, start: 0, end: 6)
			return data.count == 7 && data == Data("PMTiles".utf8)
		} catch {
			return false
		}
	}

	// MARK: - Planning (resolve tiles + exact size, no payload download)

	func makePlan(sourceURL: URL, sourceBuild: String, bounds: GeoBounds, minZoom: Int, maxZoom: Int) async throws -> Plan {
		// Header + root directory live at the start of the file; one fetch usually covers both.
		let head = try await fetchRange(sourceURL, start: 0, end: 16_383)
		guard let header = PMTilesArchive.parseHeader(head) else { throw PMTilesExtractorError.badHeader }

		let rootEntries = try await directory(
			at: header.rootDirOffset,
			length: header.rootDirLength,
			compression: header.internalCompression,
			sourceURL: sourceURL,
			prefetched: head
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
			if let range = try await resolve(tileID: tileID, header: header, root: rootEntries, sourceURL: sourceURL) {
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

		return Plan(sourceURL: sourceURL, sourceBuild: sourceBuild, header: header, bounds: bounds, minZoom: lo, maxZoom: hi, blobs: blobs, entries: entries)
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
	func extract(plan: Plan, to destination: URL, onProgress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws {
		let rootDir = Self.serializeDirectory(plan.entries)
		let metadata = Self.metadataJSON()
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

		FileManager.default.createFile(atPath: destination.path, contents: nil)
		guard let handle = try? FileHandle(forWritingTo: destination) else { throw PMTilesExtractorError.writeFailed }
		defer { try? handle.close() }

		do {
			try handle.write(contentsOf: header)
			try handle.write(contentsOf: rootDir)
			try handle.write(contentsOf: metadata)

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

				let chunk = try await fetchRange(plan.sourceURL, start: spanStart, end: spanEnd - 1)
				for blob in ordered[index...last] {
					let lower = Int(blob.sourceOffset - spanStart)
					let upper = lower + Int(blob.length)
					guard upper <= chunk.count else { throw PMTilesExtractorError.writeFailed }
					try handle.write(contentsOf: chunk.subdata(in: lower..<upper))
					written += Int64(blob.length)
				}
				onProgress?(written, total)
				index = last + 1
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

	// MARK: - Directory traversal

	private func resolve(tileID: UInt64, header: PMTilesHeader, root: [PMTilesArchive.Entry], sourceURL: URL) async throws -> (source: UInt64, length: UInt32)? {
		var dirOffset = header.rootDirOffset
		var dirLength = header.rootDirLength
		var entries = root
		for depth in 0..<4 {
			if depth > 0 {
				entries = try await directory(at: dirOffset, length: dirLength, compression: header.internalCompression, sourceURL: sourceURL, prefetched: nil)
			}
			guard let entry = PMTilesArchive.find(tileID, in: entries) else { return nil }
			if entry.runLength == 0 {
				dirOffset = header.leafDirOffset + entry.offset
				dirLength = UInt64(entry.length)
			} else {
				return (header.tileDataOffset + entry.offset, entry.length)
			}
		}
		return nil
	}

	private func directory(at offset: UInt64, length: UInt64, compression: PMTilesCompression, sourceURL: URL, prefetched: Data?) async throws -> [PMTilesArchive.Entry] {
		if let cached = leafCache[offset] { return cached }
		let raw: Data
		if let prefetched, offset + length <= UInt64(prefetched.count) {
			raw = prefetched.subdata(in: Int(offset)..<Int(offset + length))
		} else {
			raw = try await fetchRange(sourceURL, start: offset, end: offset + length - 1)
		}
		let decompressed = compression == .gzip ? (PMTilesArchive.gunzip(raw) ?? raw) : raw
		let entries = PMTilesArchive.deserializeDirectory(decompressed)
		leafCache[offset] = entries
		return entries
	}

	// MARK: - HTTP range fetch

	private func fetchRange(_ url: URL, start: UInt64, end: UInt64) async throws -> Data {
		var request = URLRequest(url: url)
		request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
		request.cachePolicy = .reloadIgnoringLocalCacheData
		let (data, response) = try await session.data(for: request)
		guard let http = response as? HTTPURLResponse else { throw PMTilesExtractorError.rangeRequestFailed(-1) }
		guard http.statusCode == 206 || http.statusCode == 200 else {
			throw PMTilesExtractorError.rangeRequestFailed(http.statusCode)
		}
		return data
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

	/// A network-free size estimate for the UI. Real size is known only after planning,
	/// but this tracks it closely enough to show while choosing an area. ~28 KB/tile is a
	/// rough average for gzipped Protomaps MVT tiles across zooms.
	static func roughByteEstimate(in bounds: GeoBounds, minZoom: Int, maxZoom: Int) -> Int64 {
		Int64(tileCount(in: bounds, minZoom: minZoom, maxZoom: maxZoom)) * 28_672
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

	static func metadataJSON() -> Data {
		let json = #"{"attribution":"© OpenStreetMap, Protomaps","name":"Meshtastic offline region"}"#
		return Data(json.utf8)
	}

	private func estimatedOverhead(_ plan: Plan) -> Int {
		Self.serializeDirectory(plan.entries).count + Self.metadataJSON().count + 127
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
