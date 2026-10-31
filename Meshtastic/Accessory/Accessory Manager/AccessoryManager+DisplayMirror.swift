//
//  AccessoryManager+DisplayMirror.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//

import Foundation
import MeshtasticProtobufs
import OSLog

/// Turns the connected radio's screen stream on and off and presses its buttons (design#142).
/// These admin messages only work over the local connection and need no session passkey; frames come back as
/// `FromRadio.display_frame` and `display_palette`.
extension AccessoryManager {

	/// Asks the radio to stream its screen for `owner`. The stream isn't kept across a reboot or
	/// reconnect, so call this again after one.
	func startDisplayMirror(for owner: DisplayMirrorOwner) {
		displayMirror.claim(owner)
		if !displayMirror.isStreaming {
			displayMirror.begin()
		}
		syncDisplayMirror()
	}

	/// Drops `owner`'s interest, and stops the stream once nobody else wants it.
	func stopDisplayMirror(for owner: DisplayMirrorOwner) {
		displayMirror.release(owner)
		if displayMirror.owners.isEmpty, displayMirror.isStreaming {
			displayMirror.end()
		}
		syncDisplayMirror()
	}

	/// Tells the radio whether to stream, one message at a time. A view can start the stream while
	/// a stop is still on its way, so each message is decided from what's wanted when it's sent,
	/// and an older stop can't land after a newer start.
	private func syncDisplayMirror() {
		guard displayMirror.commandTask == nil else { return }
		displayMirror.commandTask = Task { [weak self] in
			while let self, !Task.isCancelled {
				let wanted = displayMirror.isStreaming
				guard wanted != displayMirror.radioStreaming else { break }
				var admin = AdminMessage()
				admin.setDisplayMirror = wanted
				let sent = await sendDisplayMirrorAdmin(admin, description: wanted ? "Started screen mirroring" : "Stopped screen mirroring")
				guard !Task.isCancelled else { return }
				if sent {
					displayMirror.radioStreaming = wanted
				} else {
					// Don't leave the session marked as streaming when the request never went out,
					// so the next start tries again. A failed stop is left for the next change.
					if wanted { displayMirror.end() }
					break
				}
			}
			self?.displayMirror.commandTask = nil
		}
	}

	/// Asks for one frame now, even if the screen hasn't changed. Useful on e-ink, which redraws slowly.
	func requestDisplayFrame() async {
		var admin = AdminMessage()
		admin.getDisplayFrameRequest = true
		await sendDisplayMirrorAdmin(admin, description: "Requested a screen frame")
	}

	/// Presses a button on the radio. Touch events carry the panel pixel that was touched.
	func sendDisplayInput(_ event: DisplayInputEvent, at point: DisplayTouchPoint? = nil) async {
		var input = AdminMessage.InputEvent()
		input.eventCode = event.rawValue
		if let point {
			input.touchX = point.x
			input.touchY = point.y
		}
		var admin = AdminMessage()
		admin.sendInputEvent = input
		await sendDisplayMirrorAdmin(admin, description: "Sent screen input \(event.rawValue)")
	}

	@discardableResult
	private func sendDisplayMirrorAdmin(_ admin: AdminMessage, description: String) async -> Bool {
		guard let deviceNum = activeConnection?.device.num else {
			Logger.admin.error("Screen mirroring: no connected radio")
			return false
		}
		guard let payload = try? admin.serializedData() else {
			Logger.admin.error("Screen mirroring: couldn't encode the admin message")
			return false
		}
		var dataMessage = DataMessage()
		dataMessage.payload = payload
		dataMessage.portnum = PortNum.adminApp

		var meshPacket = MeshPacket()
		meshPacket.to = UInt32(deviceNum)
		meshPacket.from = UInt32(deviceNum)
		meshPacket.id = UInt32.random(in: UInt32(UInt8.max)..<UInt32.max)
		meshPacket.priority = .reliable
		meshPacket.decoded = dataMessage

		var toRadio = ToRadio()
		toRadio.packet = meshPacket
		do {
			try await send(toRadio, debugDescription: description)
			return true
		} catch {
			Logger.admin.error("Screen mirroring: \(description, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
			return false
		}
	}
}
