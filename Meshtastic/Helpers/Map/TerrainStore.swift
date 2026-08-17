//
//  TerrainStore.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/16/26.
//
//  Serves elevation grids from a region's downloaded Mapterhorn terrain archives.
//  All decoding happens inside the actor, off the main actor, so map rendering
//  never blocks on it. Consumers (hillshade tiles, contour generation) request
//  `ElevationTile`s for any map zoom: requests above the archived max zoom are
//  answered by bilinear-sampling the covering ancestor tile (standard DEM
//  overzoom), so terrain keeps rendering at street-level zooms.
//

import CoreLocation
import Foundation
import OSLog

/// One region's terrain data: the archive locations plus the coverage box.
struct TerrainSource: Sendable, Equatable {
	let globalURL: URL
	let regionalURL: URL?
	let bounds: GeoBounds
}

actor TerrainStore {

	/// Output grid edge length (samples per tile, before margin). Mapterhorn tiles
	/// are 512px; sampling to 256 quarters the decode-to-consumer cost and is
	/// indistinguishable under hillshade/contour rendering.
	static let tileSize = 256

	private struct OpenSource {
		let archive: PMTilesArchive
		let regional: PMTilesArchive?
		let bounds: GeoBounds
		var maxZoom: Int { Int(regional?.header.maxZoom ?? archive.header.maxZoom) }
	}

	private var sources: [OpenSource] = []
	private var configuredSources: [TerrainSource] = []
	/// Decoded raw Mapterhorn grids, LRU-evicted.
	private struct TileKey: Hashable {
		let z: Int
		let x: Int
		let y: Int
	}
	private var decodeCache: [TileKey: (size: Int, elevations: [Float])] = [:]
	private var decodeOrder: [TileKey] = []
	private let decodeCacheLimit = 24

	/// (Re)points the store at the given terrain sources. Cheap when unchanged.
	func configure(sources newSources: [TerrainSource]) {
		guard newSources != configuredSources else { return }
		configuredSources = newSources
		decodeCache.removeAll()
		decodeOrder.removeAll()
		sources = newSources.compactMap { source in
			guard let archive = PMTilesArchive(url: source.globalURL) else {
				Logger.services.error("🗺️ [Terrain] Could not open terrain archive at \(source.globalURL.lastPathComponent, privacy: .public)")
				return nil
			}
			let regional = source.regionalURL.flatMap { PMTilesArchive(url: $0) }
			return OpenSource(archive: archive, regional: regional, bounds: source.bounds)
		}
	}

	var hasSources: Bool { !sources.isEmpty }

	/// Whether any configured region covers the given tile at all.
	func covers(z: Int, x: Int, y: Int) -> Bool {
		source(covering: z, x: x, y: y) != nil
	}

	/// The coverage box of the region covering this tile, for consumers that
	/// clip rendering to the downloaded boundary.
	func coverage(z: Int, x: Int, y: Int) -> GeoBounds? {
		source(covering: z, x: x, y: y)?.bounds
	}

	/// Lon/lat box of a Web-Mercator tile.
	static func tileBounds(z: Int, x: Int, y: Int) -> GeoBounds {
		let n = Double(1 << z)
		let minLon = Double(x) / n * 360 - 180
		let maxLon = Double(x + 1) / n * 360 - 180
		let maxLat = atan(sinh(.pi * (1 - 2 * Double(y) / n))) * 180 / .pi
		let minLat = atan(sinh(.pi * (1 - 2 * Double(y + 1) / n))) * 180 / .pi
		return GeoBounds(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
	}

	/// The elevation grid for a map tile at any zoom, with `margin` edge pixels
	/// sampled from neighbors (edge-clamped at coverage boundaries). Nil when no
	/// configured region covers the tile or nothing decodes.
	func elevationTile(z: Int, x: Int, y: Int, margin: Int = 1) -> ElevationTile? {
		guard let open = source(covering: z, x: x, y: y) else { return nil }

		// Clamp to the archive's max zoom: above it, sample the covering ancestor.
		let dataZoom = min(z, open.maxZoom)
		let zoomDelta = z - dataZoom
		let scale = 1 << zoomDelta          // how many map tiles per data tile edge
		let dataX = x >> zoomDelta
		let dataY = y >> zoomDelta
		// This tile's sub-rect within the data tile, in [0, 1).
		let fracX = Double(x - dataX * scale) / Double(scale)
		let fracY = Double(y - dataY * scale) / Double(scale)

		let size = Self.tileSize
		let grid = size + 2 * margin
		var elevations = [Float](repeating: 0, count: grid * grid)

		// Sample positions span the tile plus margin, expressed in data-tile pixel
		// space (may fall outside [0, tilePx) — the sampler walks into neighbors).
		guard let baseGrid = rawGrid(open: open, z: dataZoom, x: dataX, y: dataY) else { return nil }
		let tilePx = baseGrid.size
		let span = Double(tilePx) / Double(scale)   // data pixels covered by one output tile edge
		let originX = fracX * Double(tilePx)
		let originY = fracY * Double(tilePx)
		let step = span / Double(size)
		let maxIndex = (1 << dataZoom) - 1

		// Grids memoized per neighbor offset for this call — the hot path never
		// hashes strings or re-enters the cache per sample. `nil` marks a missing
		// neighbor (decode failure or world edge).
		var neighborGrids: [TileKey: [Float]?] = [TileKey(z: dataZoom, x: dataX, y: dataY): baseGrid.elevations]
		func gridFor(tileX: Int, tileY: Int) -> [Float]? {
			let key = TileKey(z: dataZoom, x: min(max(tileX, 0), maxIndex), y: min(max(tileY, 0), maxIndex))
			if let cached = neighborGrids[key] { return cached }
			let fetched = rawGrid(open: open, z: key.z, x: key.x, y: key.y)?.elevations
			neighborGrids[key] = fetched
			return fetched
		}
		// Integer point sample: walks into the neighbor tile when the coordinate
		// leaves this one. When the neighbor is missing, clamps to THIS tile's
		// nearest edge (never the wrapped opposite edge).
		func point(_ ix: Int, _ iy: Int) -> Float {
			var tileX = dataX, tileY = dataY, lx = ix, ly = iy
			if lx < 0 { tileX -= 1; lx += tilePx } else if lx >= tilePx { tileX += 1; lx -= tilePx }
			if ly < 0 { tileY -= 1; ly += tilePx } else if ly >= tilePx { tileY += 1; ly -= tilePx }
			if tileX != dataX || tileY != dataY {
				if let neighbor = gridFor(tileX: tileX, tileY: tileY) {
					return neighbor[ly * tilePx + lx]
				}
				// Missing neighbor: clamp the ORIGINAL coordinate into the base tile.
				let cx = min(max(ix, 0), tilePx - 1)
				let cy = min(max(iy, 0), tilePx - 1)
				return baseGrid.elevations[cy * tilePx + cx]
			}
			return baseGrid.elevations[ly * tilePx + lx]
		}

		for gy in 0..<grid {
			let sy = originY + (Double(gy - margin) + 0.5) * step - 0.5
			let y0 = Int(sy.rounded(.down))
			let ty = Float(sy - Double(y0))
			for gx in 0..<grid {
				let sx = originX + (Double(gx - margin) + 0.5) * step - 0.5
				let x0 = Int(sx.rounded(.down))
				let tx = Float(sx - Double(x0))
				let p00 = point(x0, y0), p10 = point(x0 + 1, y0)
				let p01 = point(x0, y0 + 1), p11 = point(x0 + 1, y0 + 1)
				let top = p00 + (p10 - p00) * tx
				let bottom = p01 + (p11 - p01) * tx
				elevations[gy * grid + gx] = top + (bottom - top) * ty
			}
		}
		return ElevationTile(z: z, x: x, y: y, size: size, margin: margin, elevations: elevations)
	}

	// MARK: - Point queries

	/// Zoom used for single-coordinate elevation lookups: the finest zoom the
	/// global archive always carries (~30 m data), plenty for a site elevation.
	static let pointQueryZoom = 12

	/// A coordinate located within a tile grid: the tile indices plus the
	/// fractional (sample-centered) pixel position inside it.
	struct TilePixel {
		let x: Int
		let y: Int
		let px: Double
		let py: Double
	}

	/// Ground elevation in meters at a coordinate, or nil when no downloaded
	/// terrain region covers it.
	func elevation(at coordinate: CLLocationCoordinate2D) -> Double? {
		let z = Self.pointQueryZoom
		let pixel = Self.tilePixel(latitude: coordinate.latitude, longitude: coordinate.longitude, z: z, size: Self.tileSize)
		// Edge tiles are edge-clamped, so also require the coordinate itself to
		// sit inside the covering region's box — never report a clamped border
		// value for a point outside the download.
		guard let box = coverage(z: z, x: pixel.x, y: pixel.y),
			  coordinate.latitude >= box.minLat, coordinate.latitude <= box.maxLat,
			  coordinate.longitude >= box.minLon, coordinate.longitude <= box.maxLon,
			  let tile = elevationTile(z: z, x: pixel.x, y: pixel.y, margin: 1) else { return nil }
		return Double(Self.sample(tile, px: pixel.px, py: pixel.py))
	}

	/// The Web-Mercator tile containing a coordinate at zoom `z`, plus the
	/// coordinate's fractional pixel position (sample-centered) within a
	/// `size`-sample grid for that tile.
	static func tilePixel(latitude: Double, longitude: Double, z: Int, size: Int) -> TilePixel {
		let n = Double(1 << z)
		// Clamp to the Web-Mercator latitude limit so the y math stays finite.
		let lat = min(max(latitude, -85.05112878), 85.05112878)
		let lon = min(max(longitude, -180), 180)
		let xt = (lon + 180) / 360 * n
		let latRad = lat * .pi / 180
		let yt = (1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n
		let maxIndex = (1 << z) - 1
		let x = min(max(Int(xt.rounded(.down)), 0), maxIndex)
		let y = min(max(Int(yt.rounded(.down)), 0), maxIndex)
		let px = (xt - Double(x)) * Double(size) - 0.5
		let py = (yt - Double(y)) * Double(size) - 0.5
		return TilePixel(x: x, y: y, px: px, py: py)
	}

	/// Bilinear sample of a tile's elevation grid at a fractional pixel position
	/// (grid coordinates clamp at the margin, matching `gridElevation`).
	static func sample(_ tile: ElevationTile, px: Double, py: Double) -> Float {
		let x0 = Int(px.rounded(.down))
		let y0 = Int(py.rounded(.down))
		let tx = Float(px - Double(x0))
		let ty = Float(py - Double(y0))
		let p00 = tile.gridElevation(x: x0, y: y0)
		let p10 = tile.gridElevation(x: x0 + 1, y: y0)
		let p01 = tile.gridElevation(x: x0, y: y0 + 1)
		let p11 = tile.gridElevation(x: x0 + 1, y: y0 + 1)
		let top = p00 + (p10 - p00) * tx
		let bottom = p01 + (p11 - p01) * tx
		return top + (bottom - top) * ty
	}

	/// Meters-per-sample for an `ElevationTile` at the given zoom/latitude — the
	/// ground resolution consumers need for slope math.
	static func metersPerSample(z: Int, y: Int, size: Int) -> Double {
		let n = Double(1 << z)
		let latitude = atan(sinh(.pi * (1 - 2 * (Double(y) + 0.5) / n))) * 180 / .pi
		let metersPerTile = 40_075_016.686 * cos(latitude * .pi / 180) / n
		return metersPerTile / Double(size)
	}

	/// Raw decoded Mapterhorn grid for a data tile, preferring the regional
	/// archive when it has the tile. LRU-cached (hits move to the back).
	private func rawGrid(open: OpenSource, z: Int, x: Int, y: Int) -> (size: Int, elevations: [Float])? {
		let key = TileKey(z: z, x: x, y: y)
		if let cached = decodeCache[key] {
			if let position = decodeOrder.firstIndex(of: key), position != decodeOrder.count - 1 {
				decodeOrder.remove(at: position)
				decodeOrder.append(key)
			}
			return cached
		}
		var data: Data?
		if let regional = open.regional, z >= Int(regional.header.minZoom), z <= Int(regional.header.maxZoom) {
			data = regional.tileData(z: UInt8(z), x: UInt32(x), y: UInt32(y))
		}
		if data == nil {
			data = open.archive.tileData(z: UInt8(z), x: UInt32(x), y: UInt32(y))
		}
		guard let data, let decoded = TerrariumDecoder.decode(tileData: data) else { return nil }
		decodeCache[key] = decoded
		decodeOrder.append(key)
		if decodeOrder.count > decodeCacheLimit {
			decodeCache.removeValue(forKey: decodeOrder.removeFirst())
		}
		return decoded
	}

	/// The configured source whose bounds INTERSECT the tile. A center test left
	/// border tiles either spilling past the region boundary or gapped inside it;
	/// intersection + consumer-side clipping renders exactly to the boundary.
	private func source(covering z: Int, x: Int, y: Int) -> OpenSource? {
		let tile = Self.tileBounds(z: z, x: x, y: y)
		return sources.first { source in
			tile.minLon <= source.bounds.maxLon && tile.maxLon >= source.bounds.minLon &&
			tile.minLat <= source.bounds.maxLat && tile.maxLat >= source.bounds.minLat
		}
	}
}
