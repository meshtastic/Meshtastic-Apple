//
//  BurningManOfflinePack.swift
//  Meshtastic
//

import Foundation

/// Metadata for the user-controlled Burning Man offline map.
enum BurningManOfflinePack {
	static let packID = "burning-man-2026"
	static let bounds = GeoBounds(
		minLon: -119.287957,
		minLat: 40.722536,
		maxLon: -119.128520,
		maxLat: 40.843420
	)

	static func isEligible(firmwareEdition: FirmwareEditions) -> Bool {
		firmwareEdition == .burningMan
	}

	static func existingRegion(in regions: [OfflineMapRegion]) -> OfflineMapRegion? {
		regions.first { $0.systemPackID == packID }
	}
}
