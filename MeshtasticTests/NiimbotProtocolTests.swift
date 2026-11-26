//
//  NiimbotProtocolTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/25/26.
//

import CoreGraphics
import Foundation
import Testing
@testable import Meshtastic

/// The expected bytes come from labeltastic's vendored niimprint encoder, which prints on a
/// D110, run over the same pattern.
@Suite("Niimbot protocol")
struct NiimbotProtocolTests {

	private func hex(_ bytes: [UInt8]) -> String {
		bytes.map { String(format: "%02x", $0) }.joined()
	}

	@Test("Packets frame and checksum as the printer expects")
	func framing() {
		#expect(hex(NiimbotPacket(0xC1, [0x01]).bytes) == "5555c10101c1aaaa")
		let dimension: [UInt8] = [0x00, 0xEC, 0x00, 0x60, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0]
		#expect(hex(NiimbotPacket(0x13, dimension).bytes) == "5555130d00ec006000010000000000000093aaaa")
		let start: [UInt8] = [0x00, 0x01, 0, 0, 0, 0, 0, 0, 0]
		#expect(hex(NiimbotPacket(0x01, start).bytes) == "5555010900010000000000000009aaaa")
	}

	@Test("Rows encode byte for byte as labeltastic's encoder does")
	func rows() {
		var bitmap = LabelBitmap(width: 96, height: 8)
		for x in 0..<96 { bitmap.setInk(x: x, y: 0) }  // a full row: 32 dots per third
		bitmap.setInk(x: 0, y: 4)  // one dot in the first third
		for y in 5...6 {  // two identical rows: dots in the second and third thirds
			for x in [40, 41, 95] { bitmap.setInk(x: x, y: y) }
		}
		let packets = NiimbotImageEncoder.packets(for: bitmap).map { hex($0.bytes) }
		#expect(packets == [
			"55558512000020202001ffffffffffffffffffffffffb6aaaa",
			"5555840300010385aaaa",
			"5555851200040100000180000000000000000000000013aaaa",
			"555585120005000201020000000000c000000000000152aaaa",
			"5555840300070181aaaa"
		])
	}

	@Test("The parser splits, joins and skips noise between packets")
	func parsing() {
		var parser = NiimbotPacketParser()
		let a = NiimbotPacket(0xC2, [0x01]).bytes, b = NiimbotPacket(0xDD, [1, 2, 3]).bytes
		#expect(parser.append([0x00, 0x13] + Array(a.prefix(3))).isEmpty)  // noise, then half a packet
		let joined = parser.append(Array(a.dropFirst(3)) + b)
		#expect(joined == [NiimbotPacket(0xC2, [0x01]), NiimbotPacket(0xDD, [1, 2, 3])])
		var corrupt = NiimbotPacket(0xC2, [0x01]).bytes
		corrupt[5] ^= 0xFF  // bad checksum: dropped
		#expect(parser.append(corrupt).isEmpty)
	}

	@Test("A reading-orientation picture turns a quarter clockwise onto the head")
	func rotation() throws {
		// 4 wide x 2 tall, ink only at the top-left pixel.
		var pixels: [UInt8] = [0, 255, 255, 255, 255, 255, 255, 255]
		let context = try #require(CGContext(
			data: &pixels, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 4,
			space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
		let image = try #require(context.makeImage())
		let bitmap = try #require(LabelBitmap(readingOrientation: image, headDots: 8))
		#expect(bitmap.width == 8 && bitmap.height == 4)
		// Top-left of the picture lands at the first row, at the far side of the centred
		// 2-dot strip: x = inset (3) + height - 1 - 0 = 4.
		var inked: [(Int, Int)] = []
		for y in 0..<bitmap.height { for x in 0..<bitmap.width where bitmap.isInk(x: x, y: y) { inked.append((x, y)) } }
		#expect(inked.count == 1)
		#expect(inked.first?.0 == 4 && inked.first?.1 == 0)
	}
}
