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

	/// The radio to connect first at launch and to restore as the focused one, when it isn't the
	/// preferred radio: a BLE restore made another radio the focused one while this one wasn't back
	/// (T212). The preferred radio stays the focused one, which Settings and Messages follow;
	/// this only decides what's connected first. Cleared when a focus is chosen or a radio is
	/// connected as the focused one.
	static var connectFirstOverride: (peripheralId: String, nodeNum: Int64)? {
		get {
			guard let id = UserDefaults.standard.string(forKey: connectFirstIdKey), !id.isEmpty else { return nil }
			return (id, Int64(UserDefaults.standard.integer(forKey: connectFirstNumKey)))
		}
		set {
			UserDefaults.standard.set(newValue?.peripheralId, forKey: connectFirstIdKey)
			UserDefaults.standard.set(newValue.map { Int($0.nodeNum) }, forKey: connectFirstNumKey)
		}
	}
	private static let connectFirstIdKey = "multiRadio.connectFirstPeripheralId"
	private static let connectFirstNumKey = "multiRadio.connectFirstNodeNum"

	/// The radio to connect first: the override when there is one, otherwise the preferred radio.
	static var connectFirstPeripheralId: String {
		connectFirstOverride?.peripheralId ?? peripheralId
	}

	/// Whether discovery connects `peripheralId` on its own: the radio to connect first, and the
	/// preferred (focused) radio too, so a focused radio that drops while the override names
	/// another is reconnected at once rather than after the fallback (T221).
	static func connectsAutomatically(_ peripheralId: String) -> Bool {
		!peripheralId.isEmpty && (peripheralId == connectFirstPeripheralId || peripheralId == Self.peripheralId)
	}

	/// Remembers `device` as the preferred radio.
	static func set(_ device: Device) {
		peripheralId = device.id.uuidString
		nodeNum = device.num ?? 0
	}
}
