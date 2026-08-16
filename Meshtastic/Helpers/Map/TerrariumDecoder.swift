//
//  TerrariumDecoder.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/16/26.
//
//  Decodes Mapterhorn Terrarium terrain-RGB tiles (512px WebP) into elevation
//  grids. See specs/018-offline-terrain-layer/contracts/mapterhorn-data-contract.md.
//

import Foundation
import CoreGraphics
import ImageIO

/// A decoded elevation grid for one map tile, with a pixel margin borrowed from
/// neighboring tiles so downstream consumers (hillshade kernels, contour marching
/// squares) stay continuous across tile boundaries.
///
/// The grid is row-major with dimension `(size + 2 * margin)²`; index `[0, 0]` is
/// the top-left MARGIN pixel, and the tile's own top-left sample sits at
/// `[margin, margin]`. Elevations are meters.
struct ElevationTile: Sendable {
	let z: Int
	let x: Int
	let y: Int
	/// Samples per tile edge, excluding the margin.
	let size: Int
	/// Margin pixels on each edge, sampled from neighboring tiles (edge-clamped at
	/// data boundaries).
	let margin: Int
	/// Row-major `(size + 2*margin)²` elevations in meters.
	let elevations: [Float]

	var gridSize: Int { size + 2 * margin }

	/// Elevation at tile-local coordinates (0..<size), ignoring the margin offset.
	func elevation(x px: Int, y py: Int) -> Float {
		elevations[(py + margin) * gridSize + (px + margin)]
	}

	/// Elevation at grid coordinates including the margin (-margin..<size+margin).
	func gridElevation(x gx: Int, y gy: Int) -> Float {
		elevations[(gy + margin) * gridSize + (gx + margin)]
	}
}

enum TerrariumDecoder {

	/// Terrarium pixel decode: `elevation = (R × 256 + G + B ÷ 256) − 32768`.
	@inline(__always)
	static func elevation(r: UInt8, g: UInt8, b: UInt8) -> Float {
		Float(r) * 256 + Float(g) + Float(b) / 256 - 32768
	}

	/// Decodes an encoded tile image (WebP from Mapterhorn; any ImageIO-supported
	/// format works, which the tests use with PNG fixtures) into a row-major grid
	/// of elevations in meters. Returns nil for undecodable data.
	static func decode(tileData: Data) -> (size: Int, elevations: [Float])? {
		guard let source = CGImageSourceCreateWithData(tileData as CFData, nil),
			  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
			return nil
		}
		let width = image.width
		let height = image.height
		guard width > 0, width == height else { return nil }

		var rgba = [UInt8](repeating: 0, count: width * height * 4)
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		guard let context = CGContext(
			data: &rgba,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
		) else { return nil }
		context.interpolationQuality = .none
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

		var elevations = [Float](repeating: 0, count: width * height)
		for index in 0..<(width * height) {
			let base = index * 4
			elevations[index] = elevation(r: rgba[base], g: rgba[base + 1], b: rgba[base + 2])
		}
		return (width, elevations)
	}
}
