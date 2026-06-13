//
//  DeviceMetadataEntity.swift
//  Meshtastic
//
//  SwiftData model for device metadata.
//

import Foundation
import SwiftData

@Model
final class DeviceMetadataEntity {
	var canShutdown: Bool = false
	var deviceStateVersion: Int32 = 0
	var excludedModules: Int32 = 0
	var firmwareVersion: String?
	var hasBluetooth: Bool = false
	var hasBuzzer: Bool = false
	var hasEthernet: Bool = false
	var hasWifi: Bool = false
	var hwModel: String?
	var positionFlags: Int32 = 0
	var role: Int32 = 0
	var time: Date?

	var metadataNode: NodeInfoEntity?

	init() {}

	static func displayFirmwareVersion(from rawVersion: String) -> String? {
		let version = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !version.isEmpty else {
			return nil
		}

		let components = version.split(separator: ".", omittingEmptySubsequences: false)
		guard components.count > 3 else {
			return version
		}

		return components.dropLast().joined(separator: ".")
	}
}
