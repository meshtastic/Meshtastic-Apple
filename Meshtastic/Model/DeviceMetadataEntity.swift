//
//  DeviceMetadataEntity.swift
//  Meshtastic
//
//  SwiftData model for device metadata.
//

import Foundation
import SwiftData
import MeshtasticProtobufs

@Model
final class DeviceMetadataEntity {
	var canShutdown: Bool = false
	var deviceStateVersion: Int32 = 0
	var excludedModules: Int32 = 0
	var firmwareVersion: String?
	var hasBluetooth: Bool = false
	var hasEthernet: Bool = false
	var hasWifi: Bool = false
	/// Whether this firmware build includes XEdDSA packet signature verification.
	/// Read-only capability: gates the Packet Authenticity policy selector in Security config.
	var hasXeddsa: Bool = false
	var hwModel: String?
	var positionFlags: Int32 = 0
	var role: Int32 = 0
	var time: Date?
	/// The radio's screen, from `DeviceMetadata.display`. Zero width and height mean the radio
	/// reported no display: it has none, was built without screen mirroring, or runs older firmware.
	var displayWidth: Int32 = 0
	var displayHeight: Int32 = 0
	/// Raw `DisplayFrame.Format` the radio's frames will use.
	var displayFormat: Int32 = 0
	/// Raw `DisplayInfo.PanelClass`.
	var displayPanelClass: Int32 = 0
	var displayHasTouch: Bool = false

	var metadataNode: NodeInfoEntity?

	init() {}

	/// Whether the radio can stream its screen to the app.
	var hasDisplay: Bool {
		displayWidth > 0 && displayHeight > 0
	}

	func update(from metadata: DeviceMetadata) {
		time = Date()
		deviceStateVersion = Int32(metadata.deviceStateVersion)
		canShutdown = metadata.canShutdown
		hasWifi = metadata.hasWifi_p
		hasBluetooth = metadata.hasBluetooth_p
		hasEthernet = metadata.hasEthernet_p
		hasXeddsa = metadata.hasXeddsa_p
		role = Int32(metadata.role.rawValue)
		positionFlags = Int32(truncatingIfNeeded: metadata.positionFlags)
		excludedModules = Int32(truncatingIfNeeded: metadata.excludedModules)
		// Clear the display when it's absent so a downgrade doesn't leave a stale screen behind.
		let display = metadata.hasDisplay ? metadata.display : DisplayInfo()
		displayWidth = Int32(truncatingIfNeeded: display.width)
		displayHeight = Int32(truncatingIfNeeded: display.height)
		displayFormat = Int32(display.format.rawValue)
		displayPanelClass = Int32(display.panelClass.rawValue)
		displayHasTouch = display.hasTouch_p

		let lastDotIndex = metadata.firmwareVersion.lastIndex(of: ".")
		var version = metadata.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: metadata.firmwareVersion))]
		version = version.dropLast()
		firmwareVersion = String(version)
	}
}
