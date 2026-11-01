//
//  DisplayFrameAssembler.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//

import Foundation
import MeshtasticProtobufs

/// A complete screen picture from the connected radio.
struct DisplayMirrorFrame: Equatable {
	enum Format: Equatable {
		/// 1 bit per pixel, vertical LSB-first pages: byte `x + (y / 8) * width`, bit `y % 8`.
		case monoVLSB
		/// Little-endian RGB565, rows tightly packed, covering the whole panel.
		case rgb565
	}

	let width: Int
	let height: Int
	let format: Format
	let frameID: UInt32
	/// The `DisplayPalette` that colors a mono frame; 0 means plain monochrome.
	let paletteSignature: UInt32
	let pixels: Data
}

/// A complete color table for a mono frame on a color panel.
struct DisplayMirrorPalette: Equatable {
	struct Region: Equatable {
		let x: Int
		let y: Int
		let width: Int
		let height: Int
		let onColor: UInt16
		let offColor: UInt16
	}

	let signature: UInt32
	let defaultOnColor: UInt16
	let defaultOffColor: UInt16
	/// In table order; a later region wins where regions overlap.
	let regions: [Region]
}

/// Puts the radio's screen back together from `FromRadio.display_frame` and
/// `display_palette` chunks, following the rules in design#142 and mesh.proto.
///
/// Chunks of one frame arrive in order, but the radio's queue can drop one, so every chunk
/// must continue exactly where the last one ended. Anything else throws the partial frame
/// away, and an incomplete frame is never returned. Sizes come from the radio, so they're
/// checked before anything is allocated.
struct DisplayFrameAssembler {

	// 320x240 at 1 bpp is 9600 bytes.
	static let maxMonoFrameBytes = 16_384
	// Firmware's own table caps at 48 regions.
	static let maxPaletteRegions = 512

	private var buffer: Data?
	private var frameID: UInt32 = 0
	private var received = 0
	private var frameWidth = 0
	private var frameHeight = 0

	private var rects = DisplayRectCompositor()

	private var paletteRegions: [DisplayMirrorPalette.Region] = []
	private var paletteSignature: UInt32 = 0
	private var paletteTotal = 0
	/// -1 blocks continuations until the next chunk at region offset 0.
	private var paletteReceived = 0
	private var paletteDefaultOn: UInt16 = 0
	private var paletteDefaultOff: UInt16 = 0

	/// Feeds one frame chunk; returns the frame it completes, if any.
	mutating func add(_ chunk: DisplayFrame) -> DisplayMirrorFrame? {
		switch chunk.format {
		case .rgb565:
			guard rects.add(chunk), let pixels = rects.canvas else { return nil }
			return DisplayMirrorFrame(
				width: rects.width,
				height: rects.height,
				format: .rgb565,
				frameID: chunk.frameID,
				paletteSignature: 0,
				pixels: pixels
			)
		default:
			return addMono(chunk)
		}
	}

	private mutating func addMono(_ chunk: DisplayFrame) -> DisplayMirrorFrame? {
		guard Self.isAcceptableMono(chunk) else {
			buffer = nil
			return nil
		}
		if chunk.offset == 0 {
			buffer = Data(count: Int(chunk.totalSize))
			frameID = chunk.frameID
			received = 0
			// The first chunk fixes the size; a later chunk may not change it.
			frameWidth = Int(chunk.width)
			frameHeight = Int(chunk.height)
		}
		guard var current = buffer,
			  chunk.frameID == frameID,
			  Int(chunk.offset) == received,
			  current.count == Int(chunk.totalSize),
			  Int(chunk.width) == frameWidth,
			  Int(chunk.height) == frameHeight else {
			buffer = nil
			return nil
		}
		// Let go of the stored copy first so the write doesn't copy the whole buffer.
		buffer = nil
		current.replaceSubrange(received..<(received + chunk.data.count), with: chunk.data)
		received += chunk.data.count
		guard received == current.count else {
			buffer = current
			return nil
		}
		return DisplayMirrorFrame(
			width: frameWidth,
			height: frameHeight,
			format: .monoVLSB,
			frameID: frameID,
			paletteSignature: chunk.paletteSignature,
			pixels: current
		)
	}

	/// Mono only, with a width and height that describe exactly `total_size` bytes.
	private static func isAcceptableMono(_ chunk: DisplayFrame) -> Bool {
		let total = Int(chunk.totalSize)
		let width = Int(chunk.width)
		let height = Int(chunk.height)
		return chunk.format == .monoVlsb
			&& width > 0
			&& height > 0
			&& total <= maxMonoFrameBytes
			&& width * ((height + 7) / 8) == total
			&& Int(chunk.offset) <= total - chunk.data.count
	}

	/// Feeds one palette chunk; returns the palette it completes, if any.
	mutating func add(_ chunk: DisplayPalette) -> DisplayMirrorPalette? {
		if chunk.regionOffset == 0 && Int(chunk.regionTotal) <= Self.maxPaletteRegions {
			paletteRegions.removeAll(keepingCapacity: true)
			paletteSignature = chunk.signature
			paletteTotal = Int(chunk.regionTotal)
			paletteReceived = 0
			// Only the first chunk's defaults count; later chunks may leave them out.
			paletteDefaultOn = UInt16(truncatingIfNeeded: chunk.defaultOnColor)
			paletteDefaultOff = UInt16(truncatingIfNeeded: chunk.defaultOffColor)
		}
		guard paletteReceived >= 0,
			  chunk.signature == paletteSignature,
			  Int(chunk.regionOffset) == paletteReceived,
			  Int(chunk.regionTotal) == paletteTotal,
			  chunk.regions.count <= paletteTotal - paletteReceived else {
			paletteRegions.removeAll()
			paletteReceived = -1
			return nil
		}
		paletteRegions += chunk.regions.map {
			DisplayMirrorPalette.Region(
				x: Int($0.x),
				y: Int($0.y),
				width: Int($0.width),
				height: Int($0.height),
				onColor: UInt16(truncatingIfNeeded: $0.onColor),
				offColor: UInt16(truncatingIfNeeded: $0.offColor)
			)
		}
		paletteReceived += chunk.regions.count
		guard paletteReceived == paletteTotal else { return nil }
		// Complete: an extra chunk must not extend it.
		paletteReceived = -1
		return DisplayMirrorPalette(
			signature: chunk.signature,
			defaultOnColor: paletteDefaultOn,
			defaultOffColor: paletteDefaultOff,
			regions: paletteRegions
		)
	}

	/// Forgets everything, so a previous radio's screen is never shown as live.
	mutating func reset() {
		self = DisplayFrameAssembler()
	}
}

/// Paints RGB565 dirty rectangles from color-UI radios onto a saved picture of the whole panel.
struct DisplayRectCompositor {

	// The largest realistic panel is 800x480.
	static let maxPanelEdge = 1024

	private(set) var width = 0
	private(set) var height = 0
	private(set) var canvas: Data?

	private struct Area {
		let x: Int
		let y: Int
		let width: Int
		let height: Int
		let panelWidth: Int
		let panelHeight: Int
	}

	private var buffer: Data?
	private var received = 0
	private var frameID: UInt32 = 0
	private var area: Area?

	/// Feeds one chunk; returns true when it finished a rectangle and the canvas changed.
	mutating func add(_ chunk: DisplayFrame) -> Bool {
		guard isAcceptable(chunk) else {
			buffer = nil
			return false
		}
		if chunk.offset == 0 {
			buffer = Data(count: Int(chunk.totalSize))
			frameID = chunk.frameID
			received = 0
			// The first chunk fixes where the rectangle goes.
			area = Area(
				x: Int(chunk.rectX),
				y: Int(chunk.rectY),
				width: Self.rectWidth(chunk),
				height: Self.rectHeight(chunk),
				panelWidth: Int(chunk.width),
				panelHeight: Int(chunk.height)
			)
		}
		guard var current = buffer else { return false }
		buffer = nil
		current.replaceSubrange(received..<(received + chunk.data.count), with: chunk.data)
		received += chunk.data.count
		guard received == current.count else {
			buffer = current
			return false
		}
		composite(current)
		return true
	}

	/// Zero width or height means the whole panel in that direction.
	private static func rectWidth(_ chunk: DisplayFrame) -> Int {
		chunk.rectWidth > 0 ? Int(chunk.rectWidth) : Int(chunk.width)
	}

	private static func rectHeight(_ chunk: DisplayFrame) -> Int {
		chunk.rectHeight > 0 ? Int(chunk.rectHeight) : Int(chunk.height)
	}

	private func isAcceptable(_ chunk: DisplayFrame) -> Bool {
		let total = Int(chunk.totalSize)
		let expected = Self.withinPanel(chunk) ? Self.rectWidth(chunk) * Self.rectHeight(chunk) * 2 : -1
		let sized = expected == total && total > 0 && total <= Self.maxPanelEdge * Self.maxPanelEdge * 2
		// A continuation must match what the first chunk set up, not just its own claims.
		let inSequence: Bool
		if chunk.offset == 0 {
			inSequence = true
		} else if let buffer, let area {
			inSequence = buffer.count == total
				&& chunk.frameID == frameID
				&& Int(chunk.offset) == received
				&& Int(chunk.width) == area.panelWidth
				&& Int(chunk.height) == area.panelHeight
		} else {
			inSequence = false
		}
		return sized && inSequence && Int(chunk.offset) <= total - chunk.data.count
	}

	/// Checked by subtraction: `rect_x + rect_width` can overflow for bad values.
	private static func withinPanel(_ chunk: DisplayFrame) -> Bool {
		let panelWidth = Int(chunk.width)
		let panelHeight = Int(chunk.height)
		let width = rectWidth(chunk)
		let height = rectHeight(chunk)
		return (1...maxPanelEdge).contains(panelWidth)
			&& (1...maxPanelEdge).contains(panelHeight)
			&& (1...panelWidth).contains(width)
			&& (1...panelHeight).contains(height)
			&& Int(chunk.rectX) <= panelWidth - width
			&& Int(chunk.rectY) <= panelHeight - height
	}

	private mutating func composite(_ rect: Data) {
		guard let area else { return }
		if canvas == nil || width != area.panelWidth || height != area.panelHeight {
			canvas = Data(count: area.panelWidth * area.panelHeight * 2)
			width = area.panelWidth
			height = area.panelHeight
		}
		guard var target = canvas else { return }
		canvas = nil
		let rowBytes = area.width * 2
		for row in 0..<area.height {
			let source = row * rowBytes
			let destination = ((area.y + row) * width + area.x) * 2
			target.replaceSubrange(destination..<(destination + rowBytes), with: rect[source..<(source + rowBytes)])
		}
		canvas = target
	}
}
