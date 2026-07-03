//
//  PMTilesArchive.swift
//  Meshtastic
//
//  Minimal offline reader for the PMTiles v3 single-file tile archive
//  (https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md).
//
//  Scope: enough to serve individual tiles to an `MKTileOverlay` for offline display.
//  MapKit can only draw RASTER tiles, so this is intended for raster PMTiles
//  (tile type PNG / JPEG / WEBP). Vector (MVT) PMTiles parse fine here but MapKit
//  can't render them — that would require a vector renderer such as MapLibre.
//

import Compression
import Foundation
import OSLog

/// Tile payload formats a PMTiles archive can hold (header byte 99).
enum PMTilesTileType: UInt8 {
	case unknown = 0
	case mvt = 1      // vector — NOT renderable by MapKit
	case png = 2
	case jpeg = 3
	case webp = 4
	case avif = 5
}

/// Internal/tile compression codecs (header bytes 97 / 98).
enum PMTilesCompression: UInt8 {
	case unknown = 0
	case none = 1
	case gzip = 2
	case brotli = 3
	case zstd = 4
}

/// Geographic bounds in degrees.
struct GeoBounds: Equatable {
	let minLon: Double
	let minLat: Double
	let maxLon: Double
	let maxLat: Double
}

/// Parsed 127-byte PMTiles v3 header.
struct PMTilesHeader {
	let rootDirOffset: UInt64
	let rootDirLength: UInt64
	let leafDirOffset: UInt64
	let tileDataOffset: UInt64
	let internalCompression: PMTilesCompression
	let tileCompression: PMTilesCompression
	let tileType: PMTilesTileType
	let minZoom: UInt8
	let maxZoom: UInt8
	let bounds: GeoBounds
	let centerZoom: UInt8
	let center: (lon: Double, lat: Double)
}

/// Reads tiles from a local `.pmtiles` file. Thread-safe: `tileData(z:x:y:)` is called
/// from `MKTileOverlay` on background queues. The file is memory-mapped; the root
/// directory is parsed once and cached behind a lock.
final class PMTilesArchive {

	let header: PMTilesHeader
	private let data: Data
	private let lock = NSLock()
	private var rootEntries: [Entry]?
	/// Small LRU-ish cache of decoded leaf directories keyed by their byte offset.
	private var leafCache: [UInt64: [Entry]] = [:]

	/// A PMTiles directory entry. Exposed (alongside the static (de)serialization
	/// helpers below) so `PMTilesExtractor` can reuse the exact same format logic.
	struct Entry {
		var tileID: UInt64
		var offset: UInt64
		var length: UInt32
		var runLength: UInt32
	}

	// MARK: - Loading

	init?(url: URL) {
		guard let mapped = try? Data(contentsOf: url, options: .mappedIfSafe), mapped.count >= 127 else {
			Logger.services.error("📦 [PMTiles] Could not open archive at \(url.lastPathComponent, privacy: .public)")
			return nil
		}
		guard let header = PMTilesArchive.parseHeader(mapped) else {
			Logger.services.error("📦 [PMTiles] Invalid header in \(url.lastPathComponent, privacy: .public)")
			return nil
		}
		self.data = mapped
		self.header = header
		if header.tileType == .mvt {
			Logger.services.warning("📦 [PMTiles] Archive is VECTOR (MVT) — MapKit cannot render it; use a raster PMTiles.")
		}
	}

	// MARK: - Header

	static func parseHeader(_ data: Data) -> PMTilesHeader? {
		// Magic "PMTiles" + version 3.
		let magic = data.subdata(in: 0..<7)
		guard magic == Data("PMTiles".utf8), data[7] == 3 else { return nil }

		func u64(_ at: Int) -> UInt64 { data.subdata(in: at..<(at + 8)).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian } }
		func i32(_ at: Int) -> Int32 { data.subdata(in: at..<(at + 4)).withUnsafeBytes { $0.loadUnaligned(as: Int32.self).littleEndian } }

		return PMTilesHeader(
			rootDirOffset: u64(8),
			rootDirLength: u64(16),
			leafDirOffset: u64(40),
			tileDataOffset: u64(56),
			internalCompression: PMTilesCompression(rawValue: data[97]) ?? .unknown,
			tileCompression: PMTilesCompression(rawValue: data[98]) ?? .unknown,
			tileType: PMTilesTileType(rawValue: data[99]) ?? .unknown,
			minZoom: data[100],
			maxZoom: data[101],
			bounds: GeoBounds(minLon: Double(i32(102)) / 1e7, minLat: Double(i32(106)) / 1e7,
							  maxLon: Double(i32(110)) / 1e7, maxLat: Double(i32(114)) / 1e7),
			centerZoom: data[118],
			center: (Double(i32(119)) / 1e7, Double(i32(123)) / 1e7)
		)
	}

	// MARK: - Tile lookup

	/// Returns the raw tile payload for slippy-map coordinates (z, x, y), decompressed
	/// if needed, or `nil` if the archive has no tile there.
	func tileData(z: UInt8, x: UInt32, y: UInt32) -> Data? {
		guard z >= header.minZoom, z <= header.maxZoom else { return nil }
		let tileID = PMTilesArchive.zxyToTileID(z: z, x: x, y: y)

		var dirOffset = header.rootDirOffset
		var dirLength = header.rootDirLength

		// Root directory + up to a few leaf levels (spec guarantees depth ≤ 4).
		for depth in 0..<4 {
			let entries: [Entry]
			if depth == 0 {
				entries = rootDirectory()
			} else if let cached = cachedLeaf(at: dirOffset) {
				entries = cached
			} else {
				guard let raw = slice(offset: dirOffset, length: UInt32(truncatingIfNeeded: dirLength)),
					  let dir = decompress(raw, using: header.internalCompression) else { return nil }
				let parsed = PMTilesArchive.deserializeDirectory(dir)
				cacheLeaf(parsed, at: dirOffset)
				entries = parsed
			}

			guard let entry = PMTilesArchive.find(tileID, in: entries) else { return nil }

			if entry.runLength == 0 {
				// Leaf directory pointer — descend.
				dirOffset = header.leafDirOffset + entry.offset
				dirLength = UInt64(entry.length)
			} else {
				guard let raw = slice(offset: header.tileDataOffset + entry.offset, length: entry.length) else { return nil }
				return decompress(raw, using: header.tileCompression)
			}
		}
		return nil
	}

	// MARK: - Directory cache

	private func rootDirectory() -> [Entry] {
		lock.lock(); defer { lock.unlock() }
		if let cached = rootEntries { return cached }
		guard let raw = slice(offset: header.rootDirOffset, length: UInt32(truncatingIfNeeded: header.rootDirLength)),
			  let dir = decompress(raw, using: header.internalCompression) else {
			rootEntries = []
			return []
		}
		let parsed = PMTilesArchive.deserializeDirectory(dir)
		rootEntries = parsed
		return parsed
	}

	private func cachedLeaf(at offset: UInt64) -> [Entry]? {
		lock.lock(); defer { lock.unlock() }
		return leafCache[offset]
	}

	private func cacheLeaf(_ entries: [Entry], at offset: UInt64) {
		lock.lock(); defer { lock.unlock() }
		if leafCache.count > 64 { leafCache.removeAll(keepingCapacity: true) } // crude bound
		leafCache[offset] = entries
	}

	// MARK: - Byte access

	private func slice(offset: UInt64, length: UInt32) -> Data? {
		let start = Int(offset)
		let end = start + Int(length)
		guard start >= 0, end <= data.count, length > 0 else { return nil }
		return data.subdata(in: start..<end)
	}

	// MARK: - Directory deserialization

	static func deserializeDirectory(_ data: Data) -> [Entry] {
		var pos = 0
		func varint() -> UInt64 {
			var result: UInt64 = 0
			var shift: UInt64 = 0
			while pos < data.count {
				let byte = data[data.startIndex + pos]; pos += 1
				result |= UInt64(byte & 0x7F) << shift
				if byte & 0x80 == 0 { break }
				shift += 7
			}
			return result
		}

		let count = Int(varint())
		guard count > 0, count < 10_000_000 else { return [] }
		var entries = [Entry](repeating: Entry(tileID: 0, offset: 0, length: 0, runLength: 0), count: count)

		var lastID: UInt64 = 0
		for index in 0..<count { lastID += varint(); entries[index].tileID = lastID }
		for index in 0..<count { entries[index].runLength = UInt32(truncatingIfNeeded: varint()) }
		for index in 0..<count { entries[index].length = UInt32(truncatingIfNeeded: varint()) }
		for index in 0..<count {
			let value = varint()
			if value == 0 && index > 0 {
				entries[index].offset = entries[index - 1].offset + UInt64(entries[index - 1].length)
			} else {
				entries[index].offset = value - 1
			}
		}
		return entries
	}

	/// Binary search matching the PMTiles reference `findTile`.
	static func find(_ tileID: UInt64, in entries: [Entry]) -> Entry? {
		var low = 0
		var high = entries.count - 1
		while low <= high {
			let mid = (low + high) / 2
			if tileID > entries[mid].tileID {
				low = mid + 1
			} else if tileID < entries[mid].tileID {
				high = mid - 1
			} else {
				return entries[mid]
			}
		}
		// Not an exact match: the run/leaf that could contain it is at `high` (= low - 1).
		if high >= 0 {
			let entry = entries[high]
			if entry.runLength == 0 { return entry } // leaf pointer
			if tileID - entry.tileID < UInt64(entry.runLength) { return entry }
		}
		return nil
	}

	// MARK: - Hilbert tile id

	/// Converts slippy-map (z, x, y) to the PMTiles Hilbert-curve tile id.
	static func zxyToTileID(z: UInt8, x: UInt32, y: UInt32) -> UInt64 {
		// Tiles in all lower zooms: sum_{i=0}^{z-1} 4^i = (4^z - 1) / 3.
		var acc: UInt64 = 0
		for i in 0..<UInt64(z) { acc += UInt64(1) << (2 * i) }

		var rx: UInt32 = 0
		var ry: UInt32 = 0
		var dValue: UInt64 = 0
		var xx = x
		var yy = y
		var s: UInt32 = z == 0 ? 0 : (UInt32(1) << (UInt32(z) - 1))
		while s > 0 {
			rx = (xx & s) > 0 ? 1 : 0
			ry = (yy & s) > 0 ? 1 : 0
			dValue += UInt64(s) * UInt64(s) * UInt64((3 &* rx) ^ ry)
			// Rotate the quadrant.
			if ry == 0 {
				if rx == 1 {
					xx = s &- 1 &- xx
					yy = s &- 1 &- yy
				}
				swap(&xx, &yy)
			}
			s /= 2
		}
		return acc + dValue
	}

	// MARK: - Decompression

	private func decompress(_ data: Data, using compression: PMTilesCompression) -> Data? {
		switch compression {
		case .none:
			return data
		case .gzip:
			return PMTilesArchive.gunzip(data)
		case .brotli, .zstd, .unknown:
			Logger.services.error("📦 [PMTiles] Unsupported compression \(compression.rawValue) — only none/gzip handled.")
			return nil
		}
	}

	/// Inflates a gzip member using Apple's Compression framework (which only does raw
	/// DEFLATE), by parsing and skipping the gzip header and trailer.
	static func gunzip(_ data: Data) -> Data? {
		let bytes = [UInt8](data)
		guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else {
			return data // not gzip — assume already-raw payload
		}
		var index = 10
		let flags = bytes[3]
		if flags & 0x04 != 0, index + 2 <= bytes.count { // FEXTRA
			let xlen = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
			index += 2 + xlen
		}
		if flags & 0x08 != 0 { while index < bytes.count, bytes[index] != 0 { index += 1 }; index += 1 } // FNAME
		if flags & 0x10 != 0 { while index < bytes.count, bytes[index] != 0 { index += 1 }; index += 1 } // FCOMMENT
		if flags & 0x02 != 0 { index += 2 } // FHCRC
		guard index < bytes.count - 8 else { return nil }

		let deflate = data.subdata(in: (data.startIndex + index)..<(data.endIndex - 8))
		// ISIZE (uncompressed size mod 2^32) is the last 4 bytes, little-endian.
		let isize = Int(bytes[bytes.count - 4]) | (Int(bytes[bytes.count - 3]) << 8)
			| (Int(bytes[bytes.count - 2]) << 16) | (Int(bytes[bytes.count - 1]) << 24)
		return rawInflate(deflate, hint: isize > 0 ? isize : deflate.count * 8)
	}

	private static func rawInflate(_ data: Data, hint: Int) -> Data? {
		var capacity = max(hint, 4096)
		for _ in 0..<6 { // grow if the hint was too small
			let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
			defer { dst.deallocate() }
			let written = data.withUnsafeBytes { src -> Int in
				guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
				return compression_decode_buffer(dst, capacity, base, data.count, nil, COMPRESSION_ZLIB)
			}
			if written > 0 && written < capacity { return Data(bytes: dst, count: written) }
			if written == capacity { capacity *= 2; continue } // likely truncated — retry larger
			return written > 0 ? Data(bytes: dst, count: written) : nil
		}
		return nil
	}
}
