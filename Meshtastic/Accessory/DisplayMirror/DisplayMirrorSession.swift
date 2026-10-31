//
//  DisplayMirrorSession.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//

import CoreGraphics
import Foundation
import MeshtasticProtobufs

/// The views that can ask for the radio's screen. The stream stays on while any of them wants it.
enum DisplayMirrorOwner: Hashable {
	case deviceScreen
	case deviceModel
}

/// The connected radio's screen as the app last saw it. AccessoryManager feeds it chunks and
/// clears it when the connection closes, so an old screen is never shown as live.
@MainActor
@Observable
final class DisplayMirrorSession {

	/// The latest complete frame, drawn 1:1.
	private(set) var image: CGImage?
	/// Whether the app has asked the radio to stream its screen.
	private(set) var isStreaming = false
	/// Who wants the stream now.
	@ObservationIgnored private(set) var owners: Set<DisplayMirrorOwner> = []
	/// What the radio was last told, so only a change is sent.
	@ObservationIgnored var radioStreaming = false
	/// Sends the on/off changes to the radio one at a time, in order.
	@ObservationIgnored var commandTask: Task<Void, Never>?

	@ObservationIgnored private var assembler = DisplayFrameAssembler()
	@ObservationIgnored private var lastFrame: DisplayMirrorFrame?
	@ObservationIgnored private var palette: DisplayMirrorPalette?
	@ObservationIgnored private var renderTask: Task<Void, Never>?
	@ObservationIgnored private var renderPending = false
	@ObservationIgnored private var renderGeneration = 0

	/// Starts a fresh stream; the radio answers with a frame straight away.
	func begin() {
		clear()
		isStreaming = true
	}

	func end() {
		isStreaming = false
	}

	func claim(_ owner: DisplayMirrorOwner) {
		owners.insert(owner)
	}

	func release(_ owner: DisplayMirrorOwner) {
		owners.remove(owner)
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
		// The views ask again when the radio reconnects, and it has forgotten the stream.
		owners.removeAll()
		radioStreaming = false
		commandTask?.cancel()
		commandTask = nil
	}

	private func clear() {
		assembler.reset()
		lastFrame = nil
		palette = nil
		renderTask?.cancel()
		renderTask = nil
		renderPending = false
		renderGeneration += 1
		image = nil
	}

	/// Draws off the main thread: a large color panel takes a while. The last picture stays up meanwhile.
	/// Only one render runs at a time; frames that land during it are folded into one more render of the latest.
	private func render() {
		guard renderTask == nil else {
			renderPending = true
			return
		}
		guard let frame = lastFrame else { return }
		let palette = self.palette
		let generation = renderGeneration
		renderTask = Task {
			let image = await Task.detached(priority: .userInitiated) {
				DisplayFrameRenderer.image(for: frame, palette: palette)
			}.value
			// clear() bumps the generation and has already dropped this task.
			guard generation == self.renderGeneration else { return }
			self.image = image
			self.renderTask = nil
			if self.renderPending {
				self.renderPending = false
				self.render()
			}
		}
	}
}
