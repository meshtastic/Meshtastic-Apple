//
//  OTARefusal.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/2/26.
//

import Foundation

/// Turns the firmware's reason for refusing an update into something useful to the person
/// holding the radio.
///
/// An ESP32 updates over BLE or Wi-Fi by rebooting into a small loader app kept on its
/// second app partition. The firmware checks for that loader before it reboots and refuses
/// if it is missing or does not do the transport being asked for — a state only a USB flash
/// can change, so the message needs to say that rather than name a partition. Nothing in
/// device metadata reports it, which is why the app finds out by asking.
enum OTARefusal {

	/// The app's version of a firmware refusal, or nil for a message it does not recognize —
	/// in which case the radio's own wording is shown as-is. Matching is by substring: these
	/// come from firmware source, not a protocol, so the exact sentences change over time.
	static func explanation(for message: String) -> String? {
		let text = message.lowercased()

		// "Cannot find OTA Loader partition." — the flash has no room set aside for a loader.
		if text.contains("loader partition") {
			return String(localized: "This device has no partition for an update loader, so it cannot update over Bluetooth or Wi-Fi. Use the Web Flasher over USB.", comment: "OTA refused: the device's flash has no OTA loader partition")
		}
		// "Device does have a valid OTA Loader." — the partition is there but empty. The
		// firmware means "does not"; do not repeat the wording.
		if text.contains("valid ota loader") {
			return String(localized: "This device does not have an update loader installed, so it cannot update over Bluetooth or Wi-Fi. A full install with the Web Flasher over USB adds one.", comment: "OTA refused: the device has no OTA loader installed")
		}
		// "OTA Loader does not support BLE" / "WiFi"
		if text.contains("does not support") {
			return String(localized: "The update loader on this device does not support this connection. A full install with the Web Flasher over USB replaces it.", comment: "OTA refused: the installed OTA loader does not support this transport")
		}
		// "Cannot start OTA: Invalid `ota_hash` provided."
		if text.contains("ota_hash") {
			return String(localized: "The device rejected the checksum for this firmware file. Try downloading it again.", comment: "OTA refused: the device rejected the firmware hash")
		}
		// "Unable to switch to the OTA partition."
		if text.contains("switch to the ota partition") {
			return String(localized: "The device could not start its update loader. Use the Web Flasher over USB.", comment: "OTA refused: the device could not boot its OTA loader")
		}
		return nil
	}
}
