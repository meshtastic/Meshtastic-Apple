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
			guard let tile = await store.elevationTile(z: path.z, x: path.x, y: path.y, margin: 1) else {
				// Outside coverage: an empty (fully transparent) tile, not an error —
				// MapKit treats errors as retryable and would hammer loadTile. Not
				// cached: coverage can appear later via Add Terrain.
				result(Self.emptyTile, nil)
				return
			}
			let metersPerSample = TerrainStore.metersPerSample(z: path.z, y: path.y, size: tile.size)
			let png = Self.renderShadow(tile: tile, metersPerSample: metersPerSample, maxAlpha: alphaCap)
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

	/// Horn 3×3 shading over the tile's grid (the 1px margin keeps edges seamless),
	/// emitted as a black tile whose per-pixel alpha encodes shadow depth.
	static func renderShadow(tile: ElevationTile, metersPerSample: Double, maxAlpha: CGFloat) -> Data? {
		let size = tile.size
		var alphas = [UInt8](repeating: 0, count: size * size)
		let cellSize = Float(max(metersPerSample, 0.0001))
		let sinAlt = Float(sin(altitudeRadians))
		let cosAlt = Float(cos(altitudeRadians))
		let azimuth = Float(azimuthRadians)
		let cap = Float(maxAlpha)

		for py in 0..<size {
			for px in 0..<size {
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
				let shadow = max(0, (flat - illumination) / flat)
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
