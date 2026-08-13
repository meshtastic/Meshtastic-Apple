//
//  MeshBeaconConfigHelper.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//
//  Pure, view-independent helpers for the Mesh Beacon module config editor
//  (FR-009–FR-014). Kept free of SwiftUI / SwiftData so they can be unit-tested
//  in isolation (MeshBeaconConfigEditorTests):
//   - blocking validation for the beacon message (≤ 100 UTF-8 bytes) and
//     interval (≥ 3600 s), which the editor uses to block saving (FR-011/FR-013);
//   - flag bitfield get/set that preserves other bits — importantly the
//     firmware-managed FLAG_LEGACY_SPLIT (bit 4) — when toggling
//     FLAG_LISTEN_ENABLED / FLAG_BROADCAST_ENABLED (FR-010, research D4).
//

import Foundation

/// Client-side, blocking validation limits for the beacon config (never silently
/// truncate the message or clamp the interval — block the save and show why).
enum MeshBeaconValidation {
	/// Firmware caps the beacon text at 100 bytes.
	static let maxMessageBytes = 100
	/// Firmware minimum (and default) broadcast interval, in seconds.
	static let minIntervalSecs: Int32 = 3600

	/// UTF-8 byte length of the message (what the firmware limit is measured in).
	static func messageByteCount(_ message: String) -> Int {
		message.utf8.count
	}

	/// True when the message fits the firmware's byte limit (≤ 100 bytes).
	static func isMessageValid(_ message: String) -> Bool {
		messageByteCount(message) <= maxMessageBytes
	}

	/// True when the interval meets the firmware minimum (≥ 3600 s).
	static func isIntervalValid(_ secs: Int32) -> Bool {
		secs >= minIntervalSecs
	}
}

/// The beacon `flags` bitfield (mirrors `ModuleConfig.MeshBeaconConfig.Flags`).
/// Toggling one flag must preserve every other bit — especially the
/// firmware-managed `legacySplit` (bit 4), which the UI never exposes (D4).
enum MeshBeaconFlags {
	static let listenEnabled: Int32 = 1
	static let broadcastEnabled: Int32 = 2
	static let legacySplit: Int32 = 4

	/// Whether `flag` is set in `flags`.
	static func has(_ flags: Int32, _ flag: Int32) -> Bool {
		(flags & flag) != 0
	}

	/// Returns `flags` with `flag` set or cleared, leaving all other bits untouched.
	static func setting(_ flags: Int32, _ flag: Int32, to enabled: Bool) -> Int32 {
		enabled ? (flags | flag) : (flags & ~flag)
	}
}
