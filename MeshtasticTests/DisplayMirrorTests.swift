//
//  DisplayMirrorTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//

import Foundation
import Testing
import MeshtasticProtobufs
@testable import Meshtastic

/// Reassembly rules from design#142 and mesh.proto, matching Android's DisplayMirrorManagerImplTest
/// so the two apps treat the same stream the same way.
@Suite("Screen mirror reassembly")
struct DisplayFrameAssemblerTests {

	/// A 16x8 mono frame is 16 bytes; split it into chunks of `chunkSize`.
	private func monoChunks(frameID: UInt32 = 1, width: UInt32 = 16, height: UInt32 = 8, fill: UInt8 = 0xFF, chunkSize: Int = 6, palette: UInt32 = 0) -> [DisplayFrame] {
		let total = Int(width) * ((Int(height) + 7) / 8)
		let bytes = Data(repeating: fill, count: total)
		return stride(from: 0, to: total, by: chunkSize).map { offset in
			var chunk = DisplayFrame()
			chunk.width = width
			chunk.height = height
			chunk.format = .monoVlsb
			chunk.frameID = frameID
			chunk.offset = UInt32(offset)
			chunk.totalSize = UInt32(total)
			chunk.data = bytes[offset..<min(offset + chunkSize, total)]
			chunk.paletteSignature = palette
			return chunk
		}
	}

	private func feed(_ chunks: [DisplayFrame], into assembler: inout DisplayFrameAssembler) -> [DisplayMirrorFrame] {
		chunks.compactMap { assembler.add($0) }
	}

	@Test("Contiguous chunks make one frame")
	func completeFrame() {
		var assembler = DisplayFrameAssembler()
		let frames = feed(monoChunks(), into: &assembler)
		#expect(frames.count == 1)
		#expect(frames.first?.width == 16)
		#expect(frames.first?.height == 8)
		#expect(frames.first?.pixels == Data(repeating: 0xFF, count: 16))
	}

	@Test("A missing chunk drops the frame")
	func gapDropsFrame() {
		var assembler = DisplayFrameAssembler()
		var chunks = monoChunks()
		chunks.remove(at: 1)
		#expect(feed(chunks, into: &assembler).isEmpty)
	}

	@Test("A frame ID change mid-frame drops the partial frame")
	func frameIDChangeDrops() {
		var assembler = DisplayFrameAssembler()
		var chunks = monoChunks(frameID: 1)
		chunks[1].frameID = 2
		#expect(feed(chunks, into: &assembler).isEmpty)
	}

	@Test("Offset zero starts over after a broken frame")
	func recoversAtOffsetZero() {
		var assembler = DisplayFrameAssembler()
		let broken = Array(monoChunks(frameID: 1).prefix(2))
		let frames = feed(broken + monoChunks(frameID: 2, fill: 0x0F), into: &assembler)
		#expect(frames.count == 1)
		#expect(frames.first?.frameID == 2)
		#expect(frames.first?.pixels == Data(repeating: 0x0F, count: 16))
	}

	@Test("A later chunk can't change the frame size")
	func geometryIsFixedByFirstChunk() {
		var assembler = DisplayFrameAssembler()
		var chunks = monoChunks()
		// Same byte count, different shape: 8x16 instead of 16x8.
		chunks[1].width = 8
		chunks[1].height = 16
		#expect(feed(chunks, into: &assembler).isEmpty)
	}

	@Test("A size that doesn't match width and height is rejected")
	func mismatchedSizeRejected() {
		var assembler = DisplayFrameAssembler()
		var chunks = monoChunks()
		for index in chunks.indices { chunks[index].totalSize = 99 }
		#expect(feed(chunks, into: &assembler).isEmpty)
	}

	@Test("An oversized frame is rejected before allocating")
	func oversizedFrameRejected() {
		var assembler = DisplayFrameAssembler()
		var chunk = DisplayFrame()
		chunk.width = 4096
		chunk.height = 64
		chunk.format = .monoVlsb
		chunk.totalSize = 4096 * 8
		chunk.data = Data(repeating: 0, count: 10)
		#expect(assembler.add(chunk) == nil)
	}

	@Test("Unspecified format is rejected")
	func unspecifiedFormatRejected() {
		var assembler = DisplayFrameAssembler()
		var chunks = monoChunks()
		for index in chunks.indices { chunks[index].format = .unspecified }
		#expect(feed(chunks, into: &assembler).isEmpty)
	}

	@Test("Reset forgets a partial frame")
	func resetClearsPartial() {
		var assembler = DisplayFrameAssembler()
		let chunks = monoChunks()
		_ = assembler.add(chunks[0])
		assembler.reset()
		#expect(feed(Array(chunks.dropFirst()), into: &assembler).isEmpty)
	}

	// MARK: Palette

	private func paletteChunk(signature: UInt32 = 7, offset: UInt32, total: UInt32, regions: Int, defaults: Bool = true) -> DisplayPalette {
		var chunk = DisplayPalette()
		chunk.signature = signature
		chunk.regionOffset = offset
		chunk.regionTotal = total
		if defaults {
			chunk.defaultOnColor = 0xFFFF
			chunk.defaultOffColor = 0x0000
		}
		chunk.regions = (0..<regions).map { index in
			var region = DisplayPalette.ColorRegion()
			region.x = UInt32(index)
			region.width = 1
			region.height = 1
			region.onColor = 0xF800
			return region
		}
		return chunk
	}

	@Test("Palette chunks in order make a palette")
	func paletteCompletes() {
		var assembler = DisplayFrameAssembler()
		#expect(assembler.add(paletteChunk(offset: 0, total: 3, regions: 2)) == nil)
		let palette = assembler.add(paletteChunk(offset: 2, total: 3, regions: 1, defaults: false))
		#expect(palette?.regions.count == 3)
		#expect(palette?.signature == 7)
		// Defaults come from the first chunk even when a later one leaves them out.
		#expect(palette?.defaultOnColor == 0xFFFF)
	}

	@Test("A palette with a missing middle chunk is never applied")
	func paletteGapRejected() {
		var assembler = DisplayFrameAssembler()
		#expect(assembler.add(paletteChunk(offset: 0, total: 5, regions: 2)) == nil)
		// Regions 2-3 lost; the last chunk alone would satisfy offset + count == total.
		#expect(assembler.add(paletteChunk(offset: 4, total: 5, regions: 1)) == nil)
	}

	@Test("A palette chunk from another signature drops the partial palette")
	func paletteSignatureChangeRejected() {
		var assembler = DisplayFrameAssembler()
		#expect(assembler.add(paletteChunk(signature: 1, offset: 0, total: 2, regions: 1)) == nil)
		#expect(assembler.add(paletteChunk(signature: 2, offset: 1, total: 2, regions: 1)) == nil)
	}

	@Test("An extra chunk can't extend a finished palette")
	func surplusPaletteChunkRejected() {
		var assembler = DisplayFrameAssembler()
		#expect(assembler.add(paletteChunk(offset: 0, total: 1, regions: 1)) != nil)
		#expect(assembler.add(paletteChunk(offset: 1, total: 1, regions: 1)) == nil)
	}
}

@Suite("Screen mirror color rectangles")
struct DisplayRectCompositorTests {

	private func rect(x: UInt32, y: UInt32, width: UInt32, height: UInt32, panel: (UInt32, UInt32) = (4, 4), value: UInt16, frameID: UInt32 = 1) -> DisplayFrame {
		var chunk = DisplayFrame()
		chunk.width = panel.0
		chunk.height = panel.1
		chunk.format = .rgb565
		chunk.frameID = frameID
		chunk.rectX = x
		chunk.rectY = y
		chunk.rectWidth = width
		chunk.rectHeight = height
		let count = Int(width == 0 ? panel.0 : width) * Int(height == 0 ? panel.1 : height)
		chunk.totalSize = UInt32(count * 2)
		chunk.data = Data((0..<count).flatMap { _ in [UInt8(value & 0xFF), UInt8(value >> 8)] })
		return chunk
	}

	private func pixel(_ frame: DisplayMirrorFrame, x: Int, y: Int) -> UInt16 {
		let index = (y * frame.width + x) * 2
		return UInt16(frame.pixels[index]) | (UInt16(frame.pixels[index + 1]) << 8)
	}

	@Test("A rectangle is painted where it says")
	func rectIsComposited() throws {
		var assembler = DisplayFrameAssembler()
		_ = assembler.add(rect(x: 0, y: 0, width: 0, height: 0, value: 0x0000, frameID: 1))
		let completed = assembler.add(rect(x: 1, y: 2, width: 2, height: 1, value: 0xF800, frameID: 2))
		let frame = try #require(completed)
		#expect(frame.format == .rgb565)
		#expect(pixel(frame, x: 1, y: 2) == 0xF800)
		#expect(pixel(frame, x: 2, y: 2) == 0xF800)
		#expect(pixel(frame, x: 0, y: 2) == 0x0000)
		#expect(pixel(frame, x: 1, y: 1) == 0x0000)
	}

	@Test("Zero width and height cover the whole panel")
	func zeroMeansFullPanel() throws {
		var assembler = DisplayFrameAssembler()
		let completed = assembler.add(rect(x: 0, y: 0, width: 0, height: 0, value: 0x07E0))
		let frame = try #require(completed)
		#expect(frame.width == 4 && frame.height == 4)
		#expect(pixel(frame, x: 3, y: 3) == 0x07E0)
	}

	@Test("A rectangle past the panel edge is rejected")
	func outOfBoundsRejected() {
		var assembler = DisplayFrameAssembler()
		#expect(assembler.add(rect(x: 3, y: 0, width: 2, height: 1, value: 0xFFFF)) == nil)
	}

	@Test("A huge offset that would overflow is rejected")
	func overflowRejected() {
		var assembler = DisplayFrameAssembler()
		var chunk = rect(x: 0, y: 0, width: 1, height: 1, value: 0xFFFF)
		chunk.rectX = UInt32.max
		#expect(assembler.add(chunk) == nil)
	}
}

@Suite("Screen mirror drawing")
struct DisplayFrameRendererTests {

	@Test("RGB565 expands by repeating the top bits")
	func rgb565Expansion() {
		#expect(DisplayFrameRenderer.rgb(fromRGB565: 0xFFFF) == .white)
		#expect(DisplayFrameRenderer.rgb(fromRGB565: 0x0000) == .black)
		#expect(DisplayFrameRenderer.rgb(fromRGB565: 0xF800) == .init(red: 255, green: 0, blue: 0))
		#expect(DisplayFrameRenderer.rgb(fromRGB565: 0x0010).blue == 132)
	}

	private func monoFrame(byte: UInt8, palette: UInt32 = 0) -> DisplayMirrorFrame {
		// 2x8: one byte per column, bit y is row y.
		DisplayMirrorFrame(width: 2, height: 8, format: .monoVLSB, frameID: 1, paletteSignature: palette, pixels: Data([byte, 0x00]))
	}

	private func color(_ pixels: [UInt8], width: Int, x: Int, y: Int) -> DisplayFrameRenderer.RGB {
		let index = (y * width + x) * 4
		return .init(red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2])
	}

	@Test("Mono pixels read vertical LSB-first pages")
	func monoBitOrder() {
		let pixels = DisplayFrameRenderer.rgbaPixels(for: monoFrame(byte: 0b0000_0101), palette: nil)
		#expect(color(pixels, width: 2, x: 0, y: 0) == .white)
		#expect(color(pixels, width: 2, x: 0, y: 1) == .black)
		#expect(color(pixels, width: 2, x: 0, y: 2) == .white)
		#expect(color(pixels, width: 2, x: 1, y: 0) == .black)
	}

	@Test("The later palette region wins where regions overlap")
	func paletteRegionPrecedence() {
		let palette = DisplayMirrorPalette(
			signature: 9,
			defaultOnColor: 0xFFFF,
			defaultOffColor: 0x0000,
			regions: [
				.init(x: 0, y: 0, width: 2, height: 8, onColor: 0xF800, offColor: 0x0000),
				.init(x: 0, y: 0, width: 1, height: 1, onColor: 0x001F, offColor: 0x0000)
			]
		)
		let pixels = DisplayFrameRenderer.rgbaPixels(for: monoFrame(byte: 0b0000_0011, palette: 9), palette: palette)
		#expect(color(pixels, width: 2, x: 0, y: 0) == .init(red: 0, green: 0, blue: 255))
		#expect(color(pixels, width: 2, x: 0, y: 1) == .init(red: 255, green: 0, blue: 0))
	}

	@Test("A palette the frame doesn't name is ignored")
	func unreferencedPaletteIgnored() {
		let palette = DisplayMirrorPalette(signature: 9, defaultOnColor: 0xF800, defaultOffColor: 0x001F, regions: [])
		let pixels = DisplayFrameRenderer.rgbaPixels(for: monoFrame(byte: 0x01, palette: 0), palette: palette)
		#expect(color(pixels, width: 2, x: 0, y: 0) == .white)
		#expect(color(pixels, width: 2, x: 0, y: 1) == .black)
	}
}
