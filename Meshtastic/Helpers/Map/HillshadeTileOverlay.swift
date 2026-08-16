//
//  HillshadeTileOverlay.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/16/26.
//
//  Locally computed shaded relief served as raster map tiles. Elevation comes
//  from the region's downloaded Mapterhorn archives via TerrainStore; nothing
//  touches the network at render time. Horn's method (the GDAL default) with a
//  fixed light from the northwest; shadows-only output (black with variable
//  alpha) so the shading reads on both light and dark basemaps.
//

import Foundation
import MapKit
import CoreGraphics
import ImageIO
import OSLog

final class HillshadeTileOverlay: MKTileOverlay {

	private let store: TerrainStore
	/// Shadow strength cap. Dark appearance uses a lighter hand so the shading
	/// deepens rather than grays the dark basemap.
	private let maxShadowAlpha: CGFloat
	/// Rendered tiles persist here (z/x/y.png) so shading computes once per
	/// terrain download instead of on every map session. Nil disables the cache.
	private let cacheDirectory: URL?

	/// Sun position for Horn shading: standard cartographic northwest light.
	private static let azimuthRadians = 315.0 * Double.pi / 180
	private static let altitudeRadians = 45.0 * Double.pi / 180

	init(store: TerrainStore, darkAppearance: Bool, cacheDirectory: URL? = nil) {
		self.store = store
		self.maxShadowAlpha = darkAppearance ? 0.42 : 0.32
		self.cacheDirectory = cacheDirectory
		super.init(urlTemplate: nil)
		tileSize = CGSize(width: 256, height: 256)
		canReplaceMapContent = false
		minimumZ = 4
		maximumZ = 22
	}

	override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
		let store = store
		let alphaCap = maxShadowAlpha
		let cacheURL = cacheDirectory?
			.appendingPathComponent("\(path.z)-\(path.x)-\(path.y).png")
		Task.detached(priority: .utility) {
			if let cacheURL, let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
				result(cached, nil)
				return
			}
			guard let tile = await store.elevationTile(z: path.z, x: path.x, y: path.y, margin: 1),
				  let coverage = await store.coverage(z: path.z, x: path.x, y: path.y) else {
				// Outside coverage: an empty (fully transparent) tile, not an error —
				// MapKit treats errors as retryable and would hammer loadTile. Not
				// cached: coverage can appear later via Add Terrain.
				result(Self.emptyTile, nil)
				return
			}
			let metersPerSample = TerrainStore.metersPerSample(z: path.z, y: path.y, size: tile.size)
			let clip = Self.clipRect(tile: tile, path: path, coverage: coverage)
			let png = Self.renderShadow(tile: tile, metersPerSample: metersPerSample, maxAlpha: alphaCap, clip: clip)
			if let png, let cacheURL {
				try? png.write(to: cacheURL, options: .atomic)
			}
			result(png ?? Self.emptyTile, nil)
		}
	}

	// MARK: - Rendering

	/// 1×1 transparent PNG for out-of-coverage tiles.
	private static let emptyTile: Data = {
		var pixel: [UInt8] = [0, 0, 0, 0]
		let image: CGImage? = pixel.withUnsafeMutableBytes { buffer in
			CGContext(
				data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
			)?.makeImage()
		}
		guard let image, let data = pngData(from: image) else { return Data() }
		return data
	}()

	/// Pixel range of the region's coverage box within this tile, so shading is
	/// clipped exactly to the downloaded boundary. Web Mercator makes a lon/lat
	/// box a pixel-aligned rect: lon is linear in x, lat monotonic in y.
	/// Inclusive pixel bounds of the region coverage within a tile.
	struct PixelRect {
		let minX: Int
		let minY: Int
		let maxX: Int
		let maxY: Int
	}

	static func clipRect(tile: ElevationTile, path: MKTileOverlayPath, coverage: GeoBounds) -> PixelRect {
		let bounds = TerrainStore.tileBounds(z: path.z, x: path.x, y: path.y)
		let size = tile.size
		func mercY(_ latitude: Double) -> Double {
			let clamped = min(max(latitude, -85.05112878), 85.05112878)
			return 1 - asinh(tan(clamped * .pi / 180)) / .pi   // 0..2 over the world
		}
		let lonSpan = bounds.maxLon - bounds.minLon
		let x0 = Int(((coverage.minLon - bounds.minLon) / lonSpan * Double(size)).rounded(.down))
		let x1 = Int(((coverage.maxLon - bounds.minLon) / lonSpan * Double(size)).rounded(.up)) - 1
		let ySpan = mercY(bounds.minLat) - mercY(bounds.maxLat)
		let y0 = Int(((mercY(coverage.maxLat) - mercY(bounds.maxLat)) / ySpan * Double(size)).rounded(.down))
		let y1 = Int(((mercY(coverage.minLat) - mercY(bounds.maxLat)) / ySpan * Double(size)).rounded(.up)) - 1
		return PixelRect(minX: max(0, x0), minY: max(0, y0), maxX: min(size - 1, x1), maxY: min(size - 1, y1))
	}

	/// Horn 3×3 shading over the tile's grid (the 1px margin keeps edges seamless),
	/// emitted as a black tile whose per-pixel alpha encodes shadow depth. Pixels
	/// outside `clip` stay fully transparent (past the region boundary).
	static func renderShadow(tile: ElevationTile, metersPerSample: Double, maxAlpha: CGFloat, clip: PixelRect? = nil) -> Data? {
		let size = tile.size
		var alphas = [UInt8](repeating: 0, count: size * size)
		let cellSize = Float(max(metersPerSample, 0.0001))
		let sinAlt = Float(sin(altitudeRadians))
		let cosAlt = Float(cos(altitudeRadians))
		let azimuth = Float(azimuthRadians)
		let cap = Float(maxAlpha)

		let clipRange = clip ?? PixelRect(minX: 0, minY: 0, maxX: size - 1, maxY: size - 1)
		guard clipRange.minX <= clipRange.maxX, clipRange.minY <= clipRange.maxY else { return nil }
		for py in clipRange.minY...clipRange.maxY {
			for px in clipRange.minX...clipRange.maxX {
				// Horn kernel: weighted differences of the 8 neighbors. Elevations
				// clamp at sea level — the data carries ocean bathymetry, and without
				// the clamp the shading renders seafloor relief onto open water.
				let a = max(0, tile.gridElevation(x: px - 1, y: py - 1))
				let b = max(0, tile.gridElevation(x: px, y: py - 1))
				let c = max(0, tile.gridElevation(x: px + 1, y: py - 1))
				let d = max(0, tile.gridElevation(x: px - 1, y: py))
				let f = max(0, tile.gridElevation(x: px + 1, y: py))
				let g = max(0, tile.gridElevation(x: px - 1, y: py + 1))
				let h = max(0, tile.gridElevation(x: px, y: py + 1))
				let i = max(0, tile.gridElevation(x: px + 1, y: py + 1))

				let dzdx = ((c + 2 * f + i) - (a + 2 * d + g)) / (8 * cellSize)
				let dzdy = ((g + 2 * h + i) - (a + 2 * b + c)) / (8 * cellSize)

				let slope = atan(sqrt(dzdx * dzdx + dzdy * dzdy))
				let aspect = atan2(dzdy, -dzdx)
				var illumination = sinAlt * cos(slope) + cosAlt * sin(slope) * cos(azimuth - .pi / 2 - aspect)
				illumination = max(0, min(1, illumination))

				// Flat ground computes to sin(altitude) ≈ 0.707; treat that as "no
				// shadow" and scale darkness by the shortfall below it.
				let flat = sinAlt
				var shadow = max(0, (flat - illumination) / flat)
				// Fade shading out near sea level: the source data carries positive
				// sea-surface noise (measured ~1 m stdev with spikes on open water),
				// which the ≤0 m clamp can't remove. No shading below 0.5 m, full
				// above 3 m — real land that low is flat and barely shaded anyway.
				let center = max(0, tile.gridElevation(x: px, y: py))
				shadow *= min(max((center - 0.5) / 2.5, 0), 1)
				alphas[py * size + px] = UInt8(min(255, shadow * cap * 255))
			}
		}

		// Premultiplied black: RGB stays 0, alpha carries the shadow.
		var rgba = [UInt8](repeating: 0, count: size * size * 4)
		for index in 0..<(size * size) {
			rgba[index * 4 + 3] = alphas[index]
		}
		let image: CGImage? = rgba.withUnsafeMutableBytes { buffer in
			CGContext(
				data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
			)?.makeImage()
		}
		guard let image else { return nil }
		return pngData(from: image)
	}

	private static func pngData(from image: CGImage) -> Data? {
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
		CGImageDestinationAddImage(destination, image, nil)
		guard CGImageDestinationFinalize(destination) else { return nil }
		return data as Data
	}
}
