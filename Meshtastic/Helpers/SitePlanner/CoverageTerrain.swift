//
//  CoverageTerrain.swift
//  Meshtastic
//
//  Mapterhorn terrain for a coverage estimate. Every tile the coverage disc
//  touches is fetched (or read from the disk cache) and decoded before the sweep,
//  so the sweep samples elevation synchronously from an immutable snapshot.
//

import Foundation
import OSLog

/// Decoded terrain tiles for one estimate. A nil tile is sea, which Mapterhorn answers with a 404.
struct CoverageTerrain: Sendable {
	struct TileKey: Hashable, Sendable {
		let x: Int
		let y: Int
	}

	struct Tile: Sendable {
		let size: Int
		let elevations: [Float]
	}

	let zoom: Int
	let tiles: [TileKey: Tile?]

	/// Ground height at a coordinate, meters, from the nearest sample. Sea and missing tiles read 0.
	func elevation(latitude: Double, longitude: Double) -> Double {
		let probe = TerrainStore.tilePixel(latitude: latitude, longitude: longitude, z: zoom, size: 256)
		guard let entry = tiles[TileKey(x: probe.x, y: probe.y)], let tile = entry else { return 0 }
		let pixel = tile.size == 256 ? probe : TerrainStore.tilePixel(latitude: latitude, longitude: longitude, z: zoom, size: tile.size)
		let px = min(max(Int(pixel.px.rounded()), 0), tile.size - 1)
		let py = min(max(Int(pixel.py.rounded()), 0), tile.size - 1)
		return Double(tile.elevations[py * tile.size + px])
	}
}

enum CoverageTerrainLoader {
	/// The global archive's finest zoom, about 37 m per sample at mid latitudes.
	static let preferredZoom = 12
	/// Upper bound on tiles per estimate; a wider disc steps down a zoom level until it fits.
	static let maxTiles = 192
	private static let maxConcurrentFetches = 24

	enum LoadError: LocalizedError {
		case fetchFailed(Int, Int, Int)

		var errorDescription: String? {
			switch self {
			case .fetchFailed: return String(localized: "Could not download terrain for the coverage estimate.")
			}
		}
	}

	static func tileURL(z: Int, x: Int, y: Int) -> URL {
		URL(string: "https://tiles.mapterhorn.com/\(z)/\(x)/\(y).webp")!
	}

	/// Tiles at `zoom` covering a disc of `radiusKm` around a point.
	static func tileKeys(latitude: Double, longitude: Double, radiusKm: Double, zoom: Int) -> [CoverageTerrain.TileKey] {
		let latitudeSpan = radiusKm / 111.32
		let longitudeSpan = latitudeSpan / max(cos(latitude * .pi / 180), 0.01)
		let northWest = TerrainStore.tilePixel(latitude: latitude + latitudeSpan, longitude: longitude - longitudeSpan, z: zoom, size: 256)
		let southEast = TerrainStore.tilePixel(latitude: latitude - latitudeSpan, longitude: longitude + longitudeSpan, z: zoom, size: 256)
		var keys: [CoverageTerrain.TileKey] = []
		for y in northWest.y...southEast.y {
			for x in northWest.x...southEast.x {
				keys.append(CoverageTerrain.TileKey(x: x, y: y))
			}
		}
		return keys
	}

	/// The finest zoom at or below `preferredZoom` whose tiles for the disc fit in `maxTiles`.
	static func zoom(latitude: Double, longitude: Double, radiusKm: Double) -> Int {
		var zoom = preferredZoom
		while zoom > 0, tileKeys(latitude: latitude, longitude: longitude, radiusKm: radiusKm, zoom: zoom).count > maxTiles {
			zoom -= 1
		}
		return zoom
	}

	/// Fetch and decode every tile the disc touches. Only a 404 counts as sea; any other failure throws,
	/// so an estimate never runs over terrain that silently went flat.
	static func load(latitude: Double, longitude: Double, radiusKm: Double, session: URLSession = .shared) async throws -> CoverageTerrain {
		let zoom = zoom(latitude: latitude, longitude: longitude, radiusKm: radiusKm)
		let keys = tileKeys(latitude: latitude, longitude: longitude, radiusKm: radiusKm, zoom: zoom)
		let cache = cacheDirectory(zoom: zoom)
		var tiles: [CoverageTerrain.TileKey: CoverageTerrain.Tile?] = [:]
		try await withThrowingTaskGroup(of: (CoverageTerrain.TileKey, CoverageTerrain.Tile?).self) { group in
			var pending = keys.makeIterator()
			func addNext() {
				guard let key = pending.next() else { return }
				group.addTask { (key, try await tile(z: zoom, key: key, cache: cache, session: session)) }
			}
			for _ in 0..<maxConcurrentFetches { addNext() }
			for try await (key, tile) in group {
				tiles[key] = tile
				addNext()
			}
		}
		return CoverageTerrain(zoom: zoom, tiles: tiles)
	}

	private static func tile(z: Int, key: CoverageTerrain.TileKey, cache: URL?, session: URLSession) async throws -> CoverageTerrain.Tile? {
		let file = cache?.appendingPathComponent("\(key.x)-\(key.y).webp")
		if let file, let data = try? Data(contentsOf: file), let decoded = TerrariumDecoder.decode(tileData: data) {
			return CoverageTerrain.Tile(size: decoded.size, elevations: decoded.elevations)
		}
		var lastError: Error = LoadError.fetchFailed(z, key.x, key.y)
		for attempt in 0..<2 {
			try Task.checkCancellation()
			if attempt > 0 { try await Task.sleep(nanoseconds: 500_000_000) }
			do {
				let (data, response) = try await session.data(from: tileURL(z: z, x: key.x, y: key.y))
				let status = (response as? HTTPURLResponse)?.statusCode ?? 0
				if status == 404 { return nil }
				guard status == 200, let decoded = TerrariumDecoder.decode(tileData: data) else {
					lastError = LoadError.fetchFailed(z, key.x, key.y)
					continue
				}
				if let file { try? data.write(to: file, options: .atomic) }
				return CoverageTerrain.Tile(size: decoded.size, elevations: decoded.elevations)
			} catch is CancellationError {
				throw CancellationError()
			} catch {
				lastError = error
			}
		}
		Logger.services.error("🗺️ [Coverage] Terrain tile \(z)/\(key.x)/\(key.y) failed: \(lastError.localizedDescription, privacy: .public)")
		throw LoadError.fetchFailed(z, key.x, key.y)
	}

	private static func cacheDirectory(zoom: Int) -> URL? {
		guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
		let directory = caches.appendingPathComponent("terrain/coverage/\(zoom)", isDirectory: true)
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}
}
