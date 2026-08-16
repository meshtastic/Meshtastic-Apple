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
	/// Decoded raw Mapterhorn grids keyed by "z/x/y"; small LRU by insertion order.
	private var decodeCache: [String: (size: Int, elevations: [Float])] = [:]
	private var decodeOrder: [String] = []
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
		guard let probe = rawGrid(open: open, z: dataZoom, x: dataX, y: dataY) else { return nil }
		let tilePx = Double(probe.size)
		let span = tilePx / Double(scale)   // data pixels covered by one output tile edge
		let originX = fracX * tilePx
		let originY = fracY * tilePx
		let step = span / Double(size)

		for gy in 0..<grid {
			let sy = originY + (Double(gy - margin) + 0.5) * step
			for gx in 0..<grid {
				let sx = originX + (Double(gx - margin) + 0.5) * step
				elevations[gy * grid + gx] = sample(open: open, z: dataZoom, x: dataX, y: dataY, px: sx, py: sy)
			}
		}
		return ElevationTile(z: z, x: x, y: y, size: size, margin: margin, elevations: elevations)
	}

	/// Meters-per-sample for an `ElevationTile` at the given zoom/latitude — the
	/// ground resolution consumers need for slope math.
	static func metersPerSample(z: Int, y: Int, size: Int) -> Double {
		let n = Double(1 << z)
		let latitude = atan(sinh(.pi * (1 - 2 * (Double(y) + 0.5) / n))) * 180 / .pi
		let metersPerTile = 40_075_016.686 * cos(latitude * .pi / 180) / n
		return metersPerTile / Double(size)
	}

	// MARK: - Sampling

	/// Bilinear sample at data-tile pixel coordinates; walks into neighbor tiles
	/// when the position (or its +1 interpolation partner) leaves this tile.
	private func sample(open: OpenSource, z: Int, x: Int, y: Int, px: Double, py: Double) -> Float {
		func point(_ ix: Int, _ iy: Int) -> Float {
			var tileX = x, tileY = y, lx = ix, ly = iy
			guard let baseGrid = rawGrid(open: open, z: z, x: x, y: y) else { return 0 }
			let tilePx = baseGrid.size
			while lx < 0 { lx += tilePx; tileX -= 1 }
			while lx >= tilePx { lx -= tilePx; tileX += 1 }
			while ly < 0 { ly += tilePx; tileY -= 1 }
			while ly >= tilePx { ly -= tilePx; tileY += 1 }
			let maxIndex = (1 << z) - 1
			tileX = min(max(tileX, 0), maxIndex)
			tileY = min(max(tileY, 0), maxIndex)
			guard let grid = rawGrid(open: open, z: z, x: tileX, y: tileY) ?? baseGrid as (size: Int, elevations: [Float])? else { return 0 }
			let cx = min(max(lx, 0), grid.size - 1)
			let cy = min(max(ly, 0), grid.size - 1)
			return grid.elevations[cy * grid.size + cx]
		}
		let fx = px - 0.5, fy = py - 0.5
		let x0 = Int(floor(fx)), y0 = Int(floor(fy))
		let tx = Float(fx - Double(x0)), ty = Float(fy - Double(y0))
		let p00 = point(x0, y0), p10 = point(x0 + 1, y0)
		let p01 = point(x0, y0 + 1), p11 = point(x0 + 1, y0 + 1)
		let top = p00 + (p10 - p00) * tx
		let bottom = p01 + (p11 - p01) * tx
		return top + (bottom - top) * ty
	}

	/// Raw decoded Mapterhorn grid for a data tile, preferring the regional
	/// archive when it has the tile. LRU-cached.
	private func rawGrid(open: OpenSource, z: Int, x: Int, y: Int) -> (size: Int, elevations: [Float])? {
		let key = "\(z)/\(x)/\(y)"
		if let cached = decodeCache[key] { return cached }
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

	/// The configured source whose bounds contain the tile's center.
	private func source(covering z: Int, x: Int, y: Int) -> OpenSource? {
		let n = Double(1 << z)
		let lon = (Double(x) + 0.5) / n * 360 - 180
		let lat = atan(sinh(.pi * (1 - 2 * (Double(y) + 0.5) / n))) * 180 / .pi
		return sources.first { source in
			lon >= source.bounds.minLon && lon <= source.bounds.maxLon &&
			lat >= source.bounds.minLat && lat <= source.bounds.maxLat
		}
	}
}
