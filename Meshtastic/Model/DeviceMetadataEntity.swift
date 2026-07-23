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
	var hwModel: String?
	var positionFlags: Int32 = 0
	var role: Int32 = 0
	var time: Date?

	var metadataNode: NodeInfoEntity?

	init() {}

	func update(from metadata: DeviceMetadata) {
		time = Date()
		deviceStateVersion = Int32(metadata.deviceStateVersion)
		canShutdown = metadata.canShutdown
		hasWifi = metadata.hasWifi_p
		hasBluetooth = metadata.hasBluetooth_p
		hasEthernet = metadata.hasEthernet_p
		role = Int32(metadata.role.rawValue)
		positionFlags = Int32(truncatingIfNeeded: metadata.positionFlags)
		excludedModules = Int32(truncatingIfNeeded: metadata.excludedModules)

		let lastDotIndex = metadata.firmwareVersion.lastIndex(of: ".")
		var version = metadata.firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: metadata.firmwareVersion))]
		version = version.dropLast()
		firmwareVersion = String(version)
	}
}
