//
//  TerrariumDecoderTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/16/26.
//

import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import Meshtastic

@Suite("Terrarium decoder")
struct TerrariumDecoderTests {

	/// Encodes a grid of elevations into a Terrarium-RGB PNG the way Mapterhorn does.
	private func terrariumPNG(size: Int, elevation: (Int, Int) -> Double) throws -> Data {
		var rgba = [UInt8](repeating: 255, count: size * size * 4)
		for y in 0..<size {
			for x in 0..<size {
				let value = elevation(x, y) + 32768
				let r = UInt8(min(max(value / 256, 0), 255))
				let g = UInt8(min(max(value.truncatingRemainder(dividingBy: 256), 0), 255))
				let b = UInt8(min(max((value - value.rounded(.down)) * 256, 0), 255))
				let base = (y * size + x) * 4
				rgba[base] = r
				rgba[base + 1] = g
				rgba[base + 2] = b
			}
		}
		let context = try #require(CGContext(
			data: &rgba, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
		))
		let image = try #require(context.makeImage())
		let data = NSMutableData()
		let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
		CGImageDestinationAddImage(destination, image, nil)
		#expect(CGImageDestinationFinalize(destination))
		return data as Data
	}

	@Test func pixelFormulaRoundTrips() {
		// Sea level: R=128, G=0, B=0 → (128*256 + 0 + 0) − 32768 = 0.
		#expect(TerrariumDecoder.elevation(r: 128, g: 0, b: 0) == 0)
		// Everest-ish 8848m: 41616 = 162*256 + 144.
		#expect(TerrariumDecoder.elevation(r: 162, g: 144, b: 0) == 8848)
		// Below sea level: -32768 at all zeros.
		#expect(TerrariumDecoder.elevation(r: 0, g: 0, b: 0) == -32768)
	}

	@Test func decodesEncodedTile() throws {
		let png = try terrariumPNG(size: 16) { x, y in Double(x * 10 + y) }
		let decoded = try #require(TerrariumDecoder.decode(tileData: png))
		#expect(decoded.size == 16)
		#expect(abs(decoded.elevations[0] - 0) < 0.01)
		#expect(abs(decoded.elevations[5 * 16 + 3] - 35) < 0.01)
		#expect(abs(decoded.elevations[15 * 16 + 15] - 165) < 0.01)
	}

	@Test func rejectsGarbage() {
		#expect(TerrariumDecoder.decode(tileData: Data([0, 1, 2, 3])) == nil)
	}
}
