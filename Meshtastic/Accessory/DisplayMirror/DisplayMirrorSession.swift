//
//  DisplayMirrorSession.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//

import CoreGraphics
import Foundation
import MeshtasticProtobufs

/// The connected radio's screen as the app last saw it. AccessoryManager feeds it chunks and
/// clears it when the connection closes, so an old screen is never shown as live.
@MainActor
@Observable
final class DisplayMirrorSession {

	/// The latest complete frame, drawn 1:1.
	private(set) var image: CGImage?
	/// Whether the app has asked the radio to stream its screen.
	private(set) var isStreaming = false

	@ObservationIgnored private var assembler = DisplayFrameAssembler()
	@ObservationIgnored private var lastFrame: DisplayMirrorFrame?
	@ObservationIgnored private var palette: DisplayMirrorPalette?
	@ObservationIgnored private var renderTask: Task<Void, Never>?
	@ObservationIgnored private var renderGeneration = 0

	/// Starts a fresh stream; the radio answers with a frame straight away.
	func begin() {
		clear()
		isStreaming = true
	}

	func end() {
		isStreaming = false
	}

	func handle(_ chunk: DisplayFrame) {
		guard let frame = assembler.add(chunk) else { return }
		lastFrame = frame
		render()
	}

	func handle(_ chunk: DisplayPalette) {
		guard let completed = assembler.add(chunk) else { return }
		palette = completed
		// A frame that arrived before its palette turns color now.
		if let lastFrame, lastFrame.format == .monoVLSB, lastFrame.paletteSignature == completed.signature {
			render()
		}
	}

	/// Called when the connection closes.
	func reset() {
		clear()
		isStreaming = false
	}

	private func clear() {
		assembler.reset()
		lastFrame = nil
		palette = nil
		renderTask?.cancel()
		renderTask = nil
		renderGeneration += 1
		image = nil
	}

	/// Draws off the main thread: a large color panel takes a while. The last picture stays up meanwhile.
	private func render() {
		guard let frame = lastFrame else { return }
		let palette = self.palette
		renderGeneration += 1
		let generation = renderGeneration
		renderTask?.cancel()
		renderTask = Task {
			let image = await Task.detached(priority: .userInitiated) {
				DisplayFrameRenderer.image(for: frame, palette: palette)
			}.value
			guard !Task.isCancelled, generation == self.renderGeneration else { return }
			self.image = image
		}
	}
}
