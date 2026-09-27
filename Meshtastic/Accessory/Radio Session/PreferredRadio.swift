//
//  PreferredRadio.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation

/// The radio the app connects to at launch and restores in the background: the focused radio,
/// remembered across launches (feature 021).
///
/// It is not "the connected radio". Code that means the radio it's working with uses its
/// `RadioSession`, or `AccessoryManager.activeDeviceNum` for the focused one. This is the only
/// place that reads or writes `UserDefaults.preferredPeripheralId` / `preferredPeripheralNum`
/// (enforced by the `preferred_radio_defaults` SwiftLint rule, T110).
enum PreferredRadio {
	/// Its peripheral id (a BLE peripheral's UUID, or a TCP / serial device's id); empty for none.
	static var peripheralId: String {
		get { UserDefaults.preferredPeripheralId }
		set { UserDefaults.preferredPeripheralId = newValue }
	}

	/// Its node number, 0 for none.
	static var nodeNum: Int64 {
		get { Int64(UserDefaults.preferredPeripheralNum) }
		set { UserDefaults.preferredPeripheralNum = Int(newValue) }
	}

	/// Remembers `device` as the preferred radio.
	static func set(_ device: Device) {
		peripheralId = device.id.uuidString
		nodeNum = device.num ?? 0
	}
}
