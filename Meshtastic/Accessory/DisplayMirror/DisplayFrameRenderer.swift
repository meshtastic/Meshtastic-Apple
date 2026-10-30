//
//  DisplayFrameRenderer.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//

import CoreGraphics
import Foundation

/// Draws a radio screen frame into a 1:1 picture. Views scale it up with no smoothing,
/// so each radio pixel stays a crisp square.
enum DisplayFrameRenderer {

	/// 8-bit color, kept as a struct so tests can check pixels without CoreGraphics.
	struct RGB: Equatable {
		let red: UInt8
		let green: UInt8
		let blue: UInt8

		static let white = RGB(red: 255, green: 255, blue: 255)
		static let black = RGB(red: 0, green: 0, blue: 0)
	}

	/// Expands RGB565 by repeating the top bits, so full scale reaches 255.
	static func rgb(fromRGB565 value: UInt16) -> RGB {
		let r5 = UInt8((value >> 11) & 0x1F)
		let g6 = UInt8((value >> 5) & 0x3F)
		let b5 = UInt8(value & 0x1F)
		return RGB(red: (r5 << 3) | (r5 >> 2), green: (g6 << 2) | (g6 >> 4), blue: (b5 << 3) | (b5 >> 2))
	}

	/// RGBA bytes for the frame, row by row. A palette only applies when the frame names it.
	static func rgbaPixels(for frame: DisplayMirrorFrame, palette: DisplayMirrorPalette?) -> [UInt8] {
		switch frame.format {
		case .monoVLSB:
			let activePalette = palette.flatMap { frame.paletteSignature != 0 && $0.signature == frame.paletteSignature ? $0 : nil }
			return monoPixels(frame, palette: activePalette)
		case .rgb565:
			return rgb565Pixels(frame)
		}
	}

	static func image(for frame: DisplayMirrorFrame, palette: DisplayMirrorPalette?) -> CGImage? {
		let pixels = rgbaPixels(for: frame, palette: palette)
		guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
		return CGImage(
			width: frame.width,
			height: frame.height,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: frame.width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
			provider: provider,
			decode: nil,
			shouldInterpolate: false,
			intent: .defaultIntent
		)
	}

	private struct ResolvedRegion {
		let left: Int
		let top: Int
		let right: Int
		let bottom: Int
		let on: RGB
		let off: RGB
	}

	private static func monoPixels(_ frame: DisplayMirrorFrame, palette: DisplayMirrorPalette?) -> [UInt8] {
		let defaultOn = palette.map { rgb(fromRGB565: $0.defaultOnColor) } ?? .white
		let defaultOff = palette.map { rgb(fromRGB565: $0.defaultOffColor) } ?? .black
		let regions = (palette?.regions ?? []).map {
			ResolvedRegion(
				left: $0.x,
				top: $0.y,
				right: $0.x + $0.width,
				bottom: $0.y + $0.height,
				on: rgb(fromRGB565: $0.onColor),
				off: rgb(fromRGB565: $0.offColor)
			)
		}
		var out = [UInt8](repeating: 255, count: frame.width * frame.height * 4)
		frame.pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
			var rowRegions: [ResolvedRegion] = []
			rowRegions.reserveCapacity(regions.count)
			for y in 0..<frame.height {
				rowRegions.removeAll(keepingCapacity: true)
				for region in regions where y >= region.top && y < region.bottom {
					rowRegions.append(region)
				}
				let page = (y / 8) * frame.width
				let mask = UInt8(1 << (y % 8))
				for x in 0..<frame.width {
					let isSet = bytes[page + x] & mask != 0
					var color = isSet ? defaultOn : defaultOff
					// The highest-numbered region covering the pixel wins.
					for region in rowRegions.reversed() where x >= region.left && x < region.right {
						color = isSet ? region.on : region.off
						break
					}
					let index = (y * frame.width + x) * 4
					out[index] = color.red
					out[index + 1] = color.green
					out[index + 2] = color.blue
				}
			}
		}
		return out
	}

	private static func rgb565Pixels(_ frame: DisplayMirrorFrame) -> [UInt8] {
		var out = [UInt8](repeating: 255, count: frame.width * frame.height * 4)
		frame.pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
			for pixel in 0..<(frame.width * frame.height) {
				let value = UInt16(bytes[pixel * 2]) | (UInt16(bytes[pixel * 2 + 1]) << 8)
				let color = rgb(fromRGB565: value)
				out[pixel * 4] = color.red
				out[pixel * 4 + 1] = color.green
				out[pixel * 4 + 2] = color.blue
			}
		}
		return out
	}
}
