//
//  PreferredRadio.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation

/// The radio the app connects first at launch and restores first in the background, remembered
/// across launches: the last one connected that way. The other radios the user keeps connected
/// are remembered on their `MyInfoEntity` (`autoConnect`) and come back alongside it, or when
/// discovery sees them (feature 021, T317).
///
/// It is not "the radio a window shows": a window has its own (`RadioWindow`, D-19). Code that
/// means the radio it's working with uses its `RadioSession` or its window's. This is the only
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
