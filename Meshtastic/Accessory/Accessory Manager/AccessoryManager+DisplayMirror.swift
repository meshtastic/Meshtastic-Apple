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
	func startDisplayMirror(for owner: DisplayMirrorOwner) async {
		displayMirror.claim(owner)
		guard !displayMirror.isStreaming else { return }
		displayMirror.begin()
		var admin = AdminMessage()
		admin.setDisplayMirror = true
		// If the request never went out, don't leave the session marked as streaming.
		if !(await sendDisplayMirrorAdmin(admin, description: "Started screen mirroring")) {
			displayMirror.end()
		}
	}

	/// Drops `owner`'s interest, and stops the stream once nobody else wants it.
	func stopDisplayMirror(for owner: DisplayMirrorOwner) async {
		displayMirror.release(owner)
		guard displayMirror.owners.isEmpty, displayMirror.isStreaming else { return }
		displayMirror.end()
		var admin = AdminMessage()
		admin.setDisplayMirror = false
		await sendDisplayMirrorAdmin(admin, description: "Stopped screen mirroring")
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
