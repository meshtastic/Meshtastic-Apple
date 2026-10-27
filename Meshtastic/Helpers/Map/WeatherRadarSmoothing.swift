//
//  WeatherRadarSmoothing.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/26/26.
//
//  The radar is a grid of cells about 1 km across, and the map server scales it up by copying
//  cells, so zoomed in the rain is drawn in squares. Asked for at the cells' own size instead,
//  the image is softened by a fraction of a cell, scaled up smoothly, and its edge pulled back
//  to a clean line where the rain is half there, so it reads as rounded showers.
//

import CoreGraphics
import Foundation

/// The radar cells across a box, for asking the server for one pixel per cell.
struct WeatherRadarCellGrid: Equatable {
	/// One radar cell is 0.01° of longitude: this many Web Mercator meters across.
	static let cellMeters = WeatherRadar.mercatorWorldHalf * 2 / 36_000
	/// Cells asked for past the box on every side. An output pixel reads four cells through the
	/// scaling, each softened from two cells either side, so the box's edge pixels reach four cells
	/// out. With all of them fetched, neighboring tiles compute the same values where they meet.
	static let padding = 4

	/// Cells across and down the box.
	let columns: Int
	let rows: Int
	/// The box with `padding` cells more on every side, so softening and scaling see past its
	/// edges and neighboring tiles meet without a seam.
	let paddedBounds: CGRect

	var requestWidth: Int { columns + 2 * Self.padding }
	var requestHeight: Int { rows + 2 * Self.padding }

	/// The grid for Mercator `bounds` drawn at `outputWidth` by `outputHeight` pixels, or nil when
	/// a pixel is already as big as a cell and there are no squares to smooth.
	init?(bounds: CGRect, outputWidth: Int, outputHeight: Int) {
		guard bounds.width > 0, bounds.height > 0 else { return nil }
		// Cells are square in degrees, so in Mercator they're taller by 1 / cos(latitude).
		let latitude: Double = atan(sinh(Double(bounds.midY) / 6_378_137))
		let cellHeight: Double = Self.cellMeters / max(cos(latitude), 0.01)
		let columns = max(1, Int((Double(bounds.width) / Self.cellMeters).rounded()))
		let rows = max(1, Int((Double(bounds.height) / cellHeight).rounded()))
		guard columns < outputWidth, rows < outputHeight else { return nil }
		self.columns = columns
		self.rows = rows
		let padding = CGFloat(Self.padding)
		let dx = bounds.width / CGFloat(columns), dy = bounds.height / CGFloat(rows)
		paddedBounds = bounds.insetBy(dx: -dx * padding, dy: -dy * padding)
	}
}

enum WeatherRadarSmoothing {
	/// How far the cells are softened before scaling, in cells. With the scaling's own softening
	/// it rounds the steps along a shower's edge; a single cell on its own, which is mostly
	/// speckle, fades out.
	static let blurCells: Float = 0.5
	/// Where the scaled-up rain's edge is drawn: fully in from `edgeHigh`, gone below `edgeLow`.
	static let edgeLow: Float = 0.4
	static let edgeHigh: Float = 0.6

	/// The server's image of `grid.paddedBounds`, one pixel per cell, drawn smooth at `width` by
	/// `height` pixels of the unpadded box, in premultiplied RGBA.
	static func smooth(_ image: CGImage, grid: WeatherRadarCellGrid, width: Int, height: Int) -> CGImage? {
		let inWidth = grid.requestWidth, inHeight = grid.requestHeight
		guard image.width == inWidth, image.height == inHeight, width > 0, height > 0,
			  var cells = premultipliedPixels(image, width: inWidth, height: inHeight) else { return nil }
		blur(&cells, width: inWidth, height: inHeight)
		// Across, then down. The padding falls outside the output on every side.
		let across = scale(cells, rows: inHeight, from: inWidth, to: width, cells: grid.columns)
		let down = scale(across, rows: width, from: inHeight, to: height, cells: grid.rows)
		var bytes = [UInt8](repeating: 0, count: width * height * 4)
		for index in 0..<(width * height) {
			let alpha = down[index * 4 + 3]
			let kept = edgeAlpha(alpha)
			guard alpha > 0, kept > 0 else { continue }
			let factor = kept / alpha
			for channel in 0..<3 {
				bytes[index * 4 + channel] = UInt8(min(max(down[index * 4 + channel] * factor, 0), kept) * 255)
			}
			bytes[index * 4 + 3] = UInt8((kept * 255).rounded())
		}
		return bytes.withUnsafeMutableBytes { buffer in
			CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
					  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
		}
	}

	/// The pixels as premultiplied RGBA floats, 0...1, top row first.
	private static func premultipliedPixels(_ image: CGImage, width: Int, height: Int) -> [Float]? {
		var bytes = [UInt8](repeating: 0, count: width * height * 4)
		let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
										  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
			context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
			return true
		}
		return drawn ? bytes.map { Float($0) / 255 } : nil
	}

	/// A small Gaussian across and then down, holding the edge pixel past the image's edge.
	private static func blur(_ pixels: inout [Float], width: Int, height: Int) {
		let radius = 2
		var weights = (-radius...radius).map { exp(-Float($0 * $0) / (2 * blurCells * blurCells)) }
		let total = weights.reduce(0, +)
		weights = weights.map { $0 / total }
		// Across into a transposed copy, then across that, which is down the original.
		let across = convolve(pixels, rows: height, columns: width, weights: weights)
		pixels = convolve(across, rows: width, columns: height, weights: weights)
	}

	/// Runs `weights`, centered, along each row, clamping at the ends, and returns the result
	/// transposed: `columns` rows of `rows` pixels.
	private static func convolve(_ pixels: [Float], rows: Int, columns: Int, weights: [Float]) -> [Float] {
		let radius = weights.count / 2
		var result = [Float](repeating: 0, count: pixels.count)
		pixels.withUnsafeBufferPointer { input in
			result.withUnsafeMutableBufferPointer { output in
				for row in 0..<rows {
					let rowStart = row * columns * 4
					for column in 0..<columns {
						var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
						for (offset, weight) in weights.enumerated() {
							let source = rowStart + min(max(column + offset - radius, 0), columns - 1) * 4
							r += input[source] * weight
							g += input[source + 1] * weight
							b += input[source + 2] * weight
							a += input[source + 3] * weight
						}
						let target = (column * rows + row) * 4
						output[target] = r; output[target + 1] = g; output[target + 2] = b; output[target + 3] = a
					}
				}
			}
		}
		return result
	}

	/// Scales each row of RGBA pixels from `from` to `to` pixels with a cubic B-spline, which is
	/// smooth through every cell rather than passing through them in kinks. `to` covers `cells`
	/// cells, starting past the padding. The result is stored transposed, `to` rows of `rows` pixels,
	/// so a second call scales the other way and puts the image back the right way round.
	private static func scale(_ pixels: [Float], rows: Int, from: Int, to: Int, cells: Int) -> [Float] {
		// Where each output pixel reads from: the first of four cells and their weights.
		let step = Float(cells) / Float(to)
		var bases = [Int](repeating: 0, count: to)
		var weights = [Float](repeating: 0, count: to * 4)
		for out in 0..<to {
			// Cell centers sit at index + 0.5; the first output pixel is past the padding.
			let position = Float(WeatherRadarCellGrid.padding) + (Float(out) + 0.5) * step - 0.5
			let base = Int(position.rounded(.down))
			let t = position - Float(base)
			bases[out] = base - 1
			weights[out * 4] = (1 - t) * (1 - t) * (1 - t) / 6
			weights[out * 4 + 1] = (3 * t * t * t - 6 * t * t + 4) / 6
			weights[out * 4 + 2] = (-3 * t * t * t + 3 * t * t + 3 * t + 1) / 6
			weights[out * 4 + 3] = t * t * t / 6
		}
		var result = [Float](repeating: 0, count: rows * to * 4)
		pixels.withUnsafeBufferPointer { input in
			result.withUnsafeMutableBufferPointer { output in
				for row in 0..<rows {
					let rowStart = row * from * 4
					for out in 0..<to {
						var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
						for tap in 0..<4 {
							let weight = weights[out * 4 + tap]
							let source = rowStart + min(max(bases[out] + tap, 0), from - 1) * 4
							r += input[source] * weight
							g += input[source + 1] * weight
							b += input[source + 2] * weight
							a += input[source + 3] * weight
						}
						let target = (out * rows + row) * 4
						output[target] = r; output[target + 1] = g; output[target + 2] = b; output[target + 3] = a
					}
				}
			}
		}
		return result
	}

	/// How much of a pixel the sharpened edge keeps, from its softened coverage.
	static func edgeAlpha(_ alpha: Float) -> Float {
		let t = min(max((alpha - edgeLow) / (edgeHigh - edgeLow), 0), 1)
		return t * t * (3 - 2 * t)
	}
}
