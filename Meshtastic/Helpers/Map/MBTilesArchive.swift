//
//  MBTilesArchive.swift
//  Meshtastic
//
//  Minimal offline reader for an MBTiles (SQLite) raster tile archive
//  (https://github.com/mapbox/mbtiles-spec). Serves tiles to an `MKTileOverlay`.
//
//  Like the PMTiles reader, this is for RASTER tiles (PNG/JPEG/WEBP) — MapKit can't
//  render vector (pbf) tiles regardless of container.
//

import Foundation
import OSLog
import SQLite3

/// SQLite wants this for `bind_text` so it copies the string rather than referencing
/// a buffer that may be freed before the statement runs.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A local source of raster map tiles addressed by slippy-map (z, x, y).
/// Both `PMTilesArchive` and `MBTilesArchive` conform, so the MapKit shim is
/// container-agnostic.
protocol OfflineTileSource: AnyObject {
	/// Returns the (already-decompressed) tile payload: raster bytes for raster archives,
	/// or the raw MVT protobuf for vector archives (see `isVectorTiles`).
	func tileData(z: UInt8, x: UInt32, y: UInt32) -> Data?
	var tileMinZoom: UInt8 { get }
	var tileMaxZoom: UInt8 { get }
	/// Geographic extent of the archive, if known.
	var geographicBounds: GeoBounds? { get }
	/// True if the tiles are vector (MVT) and must be rasterized before MapKit can show them.
	var isVectorTiles: Bool { get }
}

// PMTilesArchive already serves tiles by z/x/y — expose it through the shared protocol.
extension PMTilesArchive: OfflineTileSource {
	var tileMinZoom: UInt8 { header.minZoom }
	var tileMaxZoom: UInt8 { header.maxZoom }
	var geographicBounds: GeoBounds? { header.bounds }
	var isVectorTiles: Bool { header.tileType == .mvt }
}

/// Reads raster tiles from a local `.mbtiles` (SQLite) file. Thread-safe: `tileData`
/// is called from `MKTileOverlay` on background queues, serialized behind a lock.
final class MBTilesArchive: OfflineTileSource {

	private var db: OpaquePointer?
	private let lock = NSLock()

	let tileMinZoom: UInt8
	let tileMaxZoom: UInt8
	let geographicBounds: GeoBounds?
	let isVectorTiles: Bool

	init?(url: URL) {
		var handle: OpaquePointer?
		guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
			Logger.services.error("📦 [MBTiles] Could not open \(url.lastPathComponent, privacy: .public)")
			if let handle { sqlite3_close(handle) }
			return nil
		}
		self.db = handle

		func metadata(_ name: String) -> String? {
			var stmt: OpaquePointer?
			guard sqlite3_prepare_v2(handle, "SELECT value FROM metadata WHERE name = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
			defer { sqlite3_finalize(stmt) }
			sqlite3_bind_text(stmt, 1, name, -1, sqliteTransient)
			guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
			return String(cString: text)
		}

		tileMinZoom = UInt8(metadata("minzoom").flatMap { Int($0) } ?? 0)
		tileMaxZoom = UInt8(metadata("maxzoom").flatMap { Int($0) } ?? 22)
		if let parts = metadata("bounds")?.split(separator: ",").compactMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
		   parts.count == 4 {
			geographicBounds = GeoBounds(minLon: parts[0], minLat: parts[1], maxLon: parts[2], maxLat: parts[3])
		} else {
			geographicBounds = nil
		}

		let format = metadata("format")?.lowercased() ?? "png"
		isVectorTiles = (format == "pbf" || format == "mvt")
	}

	deinit { if let db { sqlite3_close(db) } }

	func tileData(z: UInt8, x: UInt32, y: UInt32) -> Data? {
		guard z >= tileMinZoom, z <= tileMaxZoom else { return nil }
		// MBTiles uses the TMS scheme (row origin at the bottom); slippy-map / MapKit
		// uses the top. Flip Y: tms_y = (2^z - 1) - y.
		let flippedY = (UInt32(1) << UInt32(z)) &- 1 &- y

		lock.lock()
		defer { lock.unlock() }
		guard let db else { return nil }

		var stmt: OpaquePointer?
		let sql = "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ? LIMIT 1"
		guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
		defer { sqlite3_finalize(stmt) }

		sqlite3_bind_int(stmt, 1, Int32(z))
		sqlite3_bind_int(stmt, 2, Int32(truncatingIfNeeded: x))
		sqlite3_bind_int(stmt, 3, Int32(truncatingIfNeeded: flippedY))

		guard sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) else { return nil }
		let length = Int(sqlite3_column_bytes(stmt, 0))
		guard length > 0 else { return nil }
		return Data(bytes: blob, count: length)
	}
}

/// Opens whichever offline tile container the file extension indicates.
enum OfflineTileSourceFactory {
	static func source(for url: URL) -> OfflineTileSource? {
		switch url.pathExtension.lowercased() {
		case "pmtiles": return PMTilesArchive(url: url)
		case "mbtiles": return MBTilesArchive(url: url)
		default:
			// Try both — some files arrive without a recognized extension.
			return PMTilesArchive(url: url) ?? MBTilesArchive(url: url)
		}
	}
}
