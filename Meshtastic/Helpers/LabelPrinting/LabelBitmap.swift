//
//  LabelBitmap.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/25/26.
//

import CoreGraphics
import Foundation

/// A one-bit picture in the printer's orientation: `width` dots across the head, `height`
/// rows along the feed. Each row is packed most significant bit first, 1 for ink.
struct LabelBitmap: Equatable {
	let width: Int
	let height: Int
	private(set) var rows: [[UInt8]]

	var bytesPerRow: Int { (width + 7) / 8 }

	init(width: Int, height: Int) {
		self.width = width
		self.height = height
		rows = Array(repeating: Array(repeating: 0, count: (width + 7) / 8), count: height)
	}

	func isInk(x: Int, y: Int) -> Bool {
		rows[y][x / 8] & (0x80 >> UInt8(x % 8)) != 0
	}

	mutating func setInk(x: Int, y: Int) {
		rows[y][x / 8] |= 0x80 >> UInt8(x % 8)
	}

	/// A picture drawn in reading orientation (along the feed), turned a quarter clockwise
	/// so its height runs across the head, as labeltastic does for the D110. Anything darker
	/// than mid gray is ink: the printer can't print gray, and dithering it makes noise.
	init?(readingOrientation image: CGImage, headDots: Int) {
		guard image.height <= headDots else { return nil }
		let width = image.width, height = image.height
		var gray = [UInt8](repeating: 255, count: width * height)
		guard let context = CGContext(
			data: &gray, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
			space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
		) else { return nil }
		context.setFillColor(gray: 1, alpha: 1)
		context.fill(CGRect(x: 0, y: 0, width: width, height: height))
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		self.init(width: headDots, height: width)
		// Centred across the head when the picture is shorter than it.
		let inset = (headDots - height) / 2
		for y in 0..<height {
			for x in 0..<width where gray[y * width + x] < 128 {
				// A quarter turn clockwise: column x becomes row x, and row y becomes
				// column (height - 1 - y). CGContext memory runs top row first.
				setInk(x: inset + height - 1 - y, y: x)
			}
		}
	}
}

/// Turns a bitmap into the printer's row packets: 0x85 for a row with ink, carrying its
/// dot count in each third of the head, and 0x84 for blank rows. Identical neighbouring
/// rows go as one packet with a repeat count. Matches labeltastic's _encode_image_counted
/// byte for byte (see NiimbotProtocolTests).
enum NiimbotImageEncoder {
	static func packets(for bitmap: LabelBitmap) -> [NiimbotPacket] {
		let bytesPerRow = bitmap.bytesPerRow
		let third = bytesPerRow / 3
		var packets: [NiimbotPacket] = []
		var y = 0
		while y < bitmap.height {
			let row = bitmap.rows[y]
			var repeatCount = 1
			while y + repeatCount < bitmap.height, repeatCount < 255, bitmap.rows[y + repeatCount] == row {
				repeatCount += 1
			}
			let rowNumber = [UInt8(y >> 8), UInt8(y & 0xFF)]
			if row.allSatisfy({ $0 == 0 }) {
				packets.append(NiimbotPacket(0x84, rowNumber + [UInt8(repeatCount)]))
			} else {
				var counts: [UInt8] = [0, 0, 0]
				if third > 0, bytesPerRow <= third * 3 {
					for (index, byte) in row.enumerated() {
						counts[min(index / third, 2)] &+= UInt8(byte.nonzeroBitCount)
					}
				}
				packets.append(NiimbotPacket(0x85, rowNumber + counts + [UInt8(repeatCount)] + row))
			}
			y += repeatCount
		}
		return packets
	}
}
