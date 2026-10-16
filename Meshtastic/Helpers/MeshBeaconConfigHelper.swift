//
//  MeshBeaconConfigHelper.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//
//  Pure, view-independent helpers for the Mesh Beacon module config editor
//  (FR-009–FR-014). Kept free of SwiftUI / SwiftData so they can be unit-tested
//  in isolation (MeshBeaconConfigEditorTests):
//   - blocking validation for the beacon message (≤ 60 UTF-8 bytes) and
//     interval (≥ 3600 s), which the editor uses to block saving (FR-011/FR-013);
//   - flag bitfield get/set that preserves other bits — importantly the
//     firmware-managed FLAG_LEGACY_SPLIT (bit 4) — when toggling
//     FLAG_LISTEN_ENABLED / FLAG_BROADCAST_ENABLED (FR-010, research D4);
//   - frequency slot range checks, and the conversion between the protobuf and
//     the values the app stores and edits.
//

import Foundation
import MeshtasticProtobufs

/// Client-side, blocking validation limits for the beacon config (never silently
/// truncate the message or clamp the interval — block the save and show why).
enum MeshBeaconValidation {
	/// Firmware caps the beacon text at 60 bytes. The nanopb `max_size` is 61
	/// because it counts the terminator. Every beacon copy carries this text on
	/// the air, which is why it came down from 100.
	static let maxMessageBytes = 60
	/// Firmware minimum (and default) broadcast interval, in seconds.
	static let minIntervalSecs: Int32 = 3600

	/// UTF-8 byte length of the message (what the firmware limit is measured in).
	static func messageByteCount(_ message: String) -> Int {
		message.utf8.count
	}

	/// True when the message fits the firmware's byte limit (≤ 60 bytes).
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

// MARK: - Frequency slots

/// Frequency slots on the beacon config are 1-based and optional. 0 means unset:
/// the receiver derives the slot from the region, preset and channel name.
enum MeshBeaconSlots {
	/// How many slots `preset` has in `region`, or 0 when the region is unknown.
	static func slotCount(region: Int32, preset: Int32) -> Int {
		guard preset >= 0 else { return 0 }
		return LoRaChannelCalculator(
			regionCode: Int(region),
			usePreset: true,
			modemPreset: Int(preset),
			channelNum: 0,
			bandwidth: 0,
			overrideFrequency: 0
		).numChannels()
	}

	/// True when `slot` is unset or inside 1...`count`. A count of 0 can't be checked
	/// against, so any positive slot passes.
	static func isValid(_ slot: Int32, count: Int) -> Bool {
		if slot == 0 { return true }
		if slot < 0 { return false }
		return count <= 0 || Int(slot) <= count
	}
}

// MARK: - Config values

/// One broadcast target as the app stores it. -1 / 0 mean unset, as on the entity.
struct MeshBeaconTargetValues: Equatable {
	var preset: Int32 = -1
	var region: Int32 = 0
	var channelIndex: Int32 = -1
	var frequencySlot: Int32 = 0
}

/// The beacon config as the app stores and edits it, with the conversions to and
/// from the protobuf. The upsert and the editor both go through these so a field
/// the editor doesn't show is still kept on save.
struct MeshBeaconConfigValues: Equatable {
	var flags: Int32 = 0
	var message = ""
	var hasOfferChannel = false
	var offerChannelName = ""
	var offerChannelPSK = Data()
	var offerRegion: Int32 = 0
	/// -1 when no preset is offered.
	var offerPreset: Int32 = -1
	/// 0 when no slot is offered.
	var offerFrequencySlot: Int32 = 0
	var intervalSecs: Int32 = 3600
	var targets: [MeshBeaconTargetValues] = []

	init() {}

	init(config: ModuleConfig.MeshBeaconConfig) {
		flags = Int32(truncatingIfNeeded: config.flags)
		message = config.broadcastMessage
		hasOfferChannel = config.hasBroadcastOfferChannel
		offerChannelName = config.hasBroadcastOfferChannel ? config.broadcastOfferChannel.name : ""
		offerChannelPSK = config.hasBroadcastOfferChannel ? config.broadcastOfferChannel.psk : Data()
		offerRegion = Int32(config.broadcastOfferRegion.rawValue)
		offerPreset = config.hasBroadcastOfferPreset ? Int32(config.broadcastOfferPreset.rawValue) : -1
		offerFrequencySlot = config.hasBroadcastOfferFrequencySlot ? Int32(clamping: config.broadcastOfferFrequencySlot) : 0
		intervalSecs = config.broadcastIntervalSecs > 0 ? Int32(truncatingIfNeeded: config.broadcastIntervalSecs) : 3600
		targets = config.broadcastTargets.map { target in
			MeshBeaconTargetValues(
				preset: target.hasPreset ? Int32(target.preset.rawValue) : -1,
				region: Int32(target.region.rawValue),
				channelIndex: target.hasChannelIndex ? Int32(truncatingIfNeeded: target.channelIndex) : -1,
				frequencySlot: target.hasFrequencySlot ? Int32(clamping: target.frequencySlot) : 0
			)
		}
	}

	/// The protobuf for an admin write. Slots go out only when set; 0 is never sent.
	var config: ModuleConfig.MeshBeaconConfig {
		var config = ModuleConfig.MeshBeaconConfig()
		config.flags = UInt32(truncatingIfNeeded: flags)
		config.broadcastMessage = message
		if hasOfferChannel {
			var settings = ChannelSettings()
			settings.name = offerChannelName
			settings.psk = offerChannelPSK
			config.broadcastOfferChannel = settings
		}
		if let region = Config.LoRaConfig.RegionCode(rawValue: Int(offerRegion)) {
			config.broadcastOfferRegion = region
		}
		if offerPreset >= 0, let preset = Config.LoRaConfig.ModemPreset(rawValue: Int(offerPreset)) {
			config.broadcastOfferPreset = preset
		}
		if offerFrequencySlot > 0 {
			config.broadcastOfferFrequencySlot = UInt32(offerFrequencySlot)
		}
		config.broadcastIntervalSecs = UInt32(truncatingIfNeeded: intervalSecs)
		config.broadcastTargets = targets.map { values in
			var target = ModuleConfig.MeshBeaconConfig.BroadcastTarget()
			if values.preset >= 0, let preset = Config.LoRaConfig.ModemPreset(rawValue: Int(values.preset)) {
				target.preset = preset
			}
			if let region = Config.LoRaConfig.RegionCode(rawValue: Int(values.region)) {
				target.region = region
			}
			if values.channelIndex >= 0 {
				target.channelIndex = UInt32(values.channelIndex)
			}
			if values.frequencySlot > 0 {
				target.frequencySlot = UInt32(values.frequencySlot)
			}
			return target
		}
		return config
	}
}
