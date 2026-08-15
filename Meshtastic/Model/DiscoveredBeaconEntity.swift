// MARK: DiscoveredBeaconEntity
//
//  DiscoveredBeaconEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//
//  A MESH_BEACON_APP beacon heard during a discovery scan. Beacons advertise a
//  mesh's text message and, optionally, the channel / region / modem preset it
//  runs on. Discovery stores them per session so they can be displayed alongside
//  the per-preset results, and auto-adds any advertised preset to the scan queue.
//

import Foundation
import SwiftData

@Model
final class DiscoveredBeaconEntity {
	var nodeNum: Int64 = 0
	var shortName: String = ""
	var longName: String = ""
	/// Human-readable beacon text (MeshBeacon.message).
	var message: String = ""
	/// RegionCodes raw value advertised by the beacon; 0 = unset / not offered.
	var offerRegion: Int = 0
	/// ModemPresets raw value advertised by the beacon, or -1 when the beacon
	/// didn't offer one. (0 is a valid preset — LongFast — so nil can't be 0.)
	var offerPreset: Int = -1
	/// Name of the channel the beacon offered, when it advertised one.
	var offerChannelName: String = ""
	/// Pre-shared key of the offered channel. Broadcast in the beacon (not a local secret), and
	/// required to actually tune to / join the advertised mesh.
	var offerChannelPSK: Data = Data()
	var hasOfferChannel: Bool = false
	var snr: Float = 0.0
	var rssi: Int = 0
	var timestamp: Date = Date()
	/// The scan preset the radio was dwelling on when this beacon was heard.
	var heardOnPresetName: String = ""

	var session: DiscoverySessionEntity?
	var presetResult: DiscoveryPresetResultEntity?

	init() {}

	/// The advertised modem preset, or `nil` when the beacon didn't offer one.
	var offeredPreset: ModemPresets? {
		offerPreset >= 0 ? ModemPresets(rawValue: offerPreset) : nil
	}

	/// The advertised region, or `nil` when unset.
	var offeredRegion: RegionCodes? {
		offerRegion > 0 ? RegionCodes(rawValue: offerRegion) : nil
	}

	/// A node label for display, preferring the long name, then short, then the hex id.
	var displayName: String {
		if !longName.isEmpty { return longName }
		if !shortName.isEmpty { return shortName }
		return String(format: "!%08x", UInt32(truncatingIfNeeded: nodeNum))
	}
}
