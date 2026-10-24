//
//  CoverageTerrain.swift
//  Meshtastic
//
//  Mapterhorn terrain for a coverage estimate. Every tile the coverage disc
//  touches is read from downloaded offline terrain, the disk cache or the network
//  and decoded before the sweep, so the sweep samples elevation synchronously
//  from an immutable snapshot.
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
		let longitude = Self.wrapped(longitude)
		let probe = TerrainStore.tilePixel(latitude: latitude, longitude: longitude, z: zoom, size: 256)
		guard let entry = tiles[TileKey(x: probe.x, y: probe.y)], let tile = entry else { return 0 }
		let pixel = tile.size == 256 ? probe : TerrainStore.tilePixel(latitude: latitude, longitude: longitude, z: zoom, size: tile.size)
		let px = min(max(Int(pixel.px.rounded()), 0), tile.size - 1)
		let py = min(max(Int(pixel.py.rounded()), 0), tile.size - 1)
		return Double(tile.elevations[py * tile.size + px])
	}

	/// A longitude in -180...180. A radial that crosses the antimeridian walks past ±180, which
	/// `TerrainStore.tilePixel` would clamp to the edge tile.
	static func wrapped(_ longitude: Double) -> Double {
		let remainder = (longitude + 180).truncatingRemainder(dividingBy: 360)
		return (remainder < 0 ? remainder + 360 : remainder) - 180
	}
}

enum CoverageTerrainLoader {
	/// The global archive's finest zoom, about 37 m per sample at mid latitudes.
	static let preferredZoom = 12
	/// Upper bound on tiles per estimate; a wider disc steps down a zoom level until it fits.
	static let maxTiles = 192
	private static let maxConcurrentFetches = 24
	/// How long a 404 is trusted as sea before the tile is asked for again.
	private static let seaMarkerLifetime: TimeInterval = 3 * 24 * 60 * 60
	/// Matches `LocalCoverage`'s sphere, so the tile box holds every point the sweep walks to.
	private static let earthRadiusKm = 6371.0

	/// Tile requests give up after 15 s rather than URLSession's default 60 s, so a stalled
	/// connection fails the estimate instead of leaving the spinner up for minutes.
	static let tileSession: URLSession = {
		let configuration = URLSessionConfiguration.default
		configuration.timeoutIntervalForRequest = 15
		return URLSession(configuration: configuration)
	}()

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

	/// Tiles at `zoom` covering a disc of `radiusKm` around a point. The box is the disc's extent on the
	/// sweep's sphere (its widest longitude is poleward of the site), plus 1% and one profile step.
	static func tileKeys(latitude: Double, longitude: Double, radiusKm: Double, zoom: Int) -> [CoverageTerrain.TileKey] {
		let angle = (radiusKm * 1.01 + LocalCoverage.defaultProfileStepKm) / earthRadiusKm
		let latitudeSpan = angle * 180 / .pi
		let longitudeSpan = asin(min(1, sin(angle) / max(cos(latitude * .pi / 180), 0.0001))) * 180 / .pi
		let west = CoverageTerrain.wrapped(longitude - longitudeSpan)
		let east = CoverageTerrain.wrapped(longitude + longitudeSpan)
		let northWest = TerrainStore.tilePixel(latitude: latitude + latitudeSpan, longitude: west, z: zoom, size: 256)
		let southEast = TerrainStore.tilePixel(latitude: latitude - latitudeSpan, longitude: east, z: zoom, size: 256)
		// Across the antimeridian the west edge has the higher tile index, so the columns wrap.
		let columns = northWest.x <= southEast.x
			? Array(northWest.x...southEast.x)
			: Array(northWest.x..<(1 << zoom)) + Array(0...southEast.x)
		var keys: [CoverageTerrain.TileKey] = []
		for y in northWest.y...southEast.y {
			for x in columns {
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

	/// Fetch and decode every tile the disc touches, from `offlineSources` (downloaded Offline Maps terrain)
	/// first. Only a 404 counts as sea; any other failure throws, so an estimate never runs over terrain
	/// that silently went flat.
	static func load(
		latitude: Double,
		longitude: Double,
		radiusKm: Double,
		offlineSources: [TerrainSource] = [],
		session: URLSession = tileSession
	) async throws -> CoverageTerrain {
		let zoom = zoom(latitude: latitude, longitude: longitude, radiusKm: radiusKm)
		let keys = tileKeys(latitude: latitude, longitude: longitude, radiusKm: radiusKm, zoom: zoom)
		let cache = cacheDirectory(zoom: zoom)
		var offline: TerrainStore?
		if !offlineSources.isEmpty {
			let store = TerrainStore()
			await store.configure(sources: offlineSources)
			if await store.hasSources { offline = store }
		}
		var tiles: [CoverageTerrain.TileKey: CoverageTerrain.Tile?] = [:]
		try await withThrowingTaskGroup(of: (CoverageTerrain.TileKey, CoverageTerrain.Tile?).self) { group in
			var pending = keys.makeIterator()
			func addNext() {
				guard let key = pending.next() else { return }
				group.addTask { (key, try await tile(z: zoom, key: key, cache: cache, offline: offline, session: session)) }
			}
			for _ in 0..<maxConcurrentFetches { addNext() }
			for try await (key, tile) in group {
				tiles[key] = tile
				addNext()
			}
		}
		return CoverageTerrain(zoom: zoom, tiles: tiles)
	}

	private static func tile(z: Int, key: CoverageTerrain.TileKey, cache: URL?, offline: TerrainStore?, session: URLSession) async throws -> CoverageTerrain.Tile? {
		if let offline {
			switch await offline.coverageTile(z: z, x: key.x, y: key.y) {
			case .data(let data):
				// Decoded here rather than in the store, so tiles decode in parallel.
				if let decoded = TerrariumDecoder.decode(tileData: data) {
					return CoverageTerrain.Tile(size: decoded.size, elevations: decoded.elevations)
				}
			case .sea:
				return nil
			case .notHeld:
				break
			}
		}
		let file = cache?.appendingPathComponent("\(key.x)-\(key.y).webp")
		// An empty marker records a sea tile, so a coastal estimate doesn't refetch every 404. After a few days
		// the tile is asked for again, so a land tile that 404'd by mistake (during an archive update, say) is
		// retried. The old marker is kept until the network answers, so an offline run still treats it as sea.
		let seaMarker = cache?.appendingPathComponent("\(key.x)-\(key.y).sea")
		var hasExpiredSeaMarker = false
		if let seaMarker, let written = (try? FileManager.default.attributesOfItem(atPath: seaMarker.path))?[.modificationDate] as? Date {
			if Date().timeIntervalSince(written) < seaMarkerLifetime { return nil }
			hasExpiredSeaMarker = true
		}
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
				if status == 404 {
					if let seaMarker { try? Data().write(to: seaMarker, options: .atomic) }
					return nil
				}
				guard status == 200, let decoded = TerrariumDecoder.decode(tileData: data) else {
					lastError = LoadError.fetchFailed(z, key.x, key.y)
					continue
				}
				if let file { try? data.write(to: file, options: .atomic) }
				if hasExpiredSeaMarker, let seaMarker { try? FileManager.default.removeItem(at: seaMarker) }
				return CoverageTerrain.Tile(size: decoded.size, elevations: decoded.elevations)
			} catch is CancellationError {
				throw CancellationError()
			} catch {
				// URLSession reports a cancelled task as URLError(.cancelled), not CancellationError.
				if Task.isCancelled { throw CancellationError() }
				lastError = error
			}
		}
		// No answer from the network: an expired marker is still the best guess.
		if hasExpiredSeaMarker { return nil }
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
