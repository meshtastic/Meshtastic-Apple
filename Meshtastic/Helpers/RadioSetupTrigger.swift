//
//  RadioSetupTrigger.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//

import Foundation

/// When the radio setup flow opens on its own: once per radio, the first time it is
/// connected with no LoRa region, and only when nothing else is in the way.
struct RadioSetupTrigger {
	var nodeNum: Int64?
	/// The connected radio's region as a raw `RegionCode`; nil until its config arrives.
	var regionCode: Int?
	/// Radios the flow has already opened for by itself.
	var offered: Set<Int64>
	var isSubscribed: Bool
	var isFirstLaunchFlowShowing: Bool
	var isLockdownBlocking: Bool
	var isFirmwareGateActive: Bool
	var isDatabaseResetting: Bool

	var shouldPresent: Bool {
		guard let nodeNum, let regionCode, isSubscribed else { return false }
		guard !isFirstLaunchFlowShowing, !isLockdownBlocking, !isFirmwareGateActive, !isDatabaseResetting else { return false }
		return regionCode == RegionCodes.unset.rawValue && !offered.contains(nodeNum)
	}
}
