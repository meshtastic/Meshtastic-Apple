//
//  BluetoothModes.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/19/22.
//
import Foundation
import MeshtasticProtobufs

enum BluetoothModes: Int, CaseIterable, Identifiable {

	case randomPin = 0
	case fixedPin = 1
	case noPin = 2

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .randomPin:
			return NSLocalizedString("bluetooth.mode.randompin", comment: "No comment provided")
		case .fixedPin:
			return NSLocalizedString("bluetooth.mode.fixedpin", comment: "No comment provided")
		case .noPin:
			return NSLocalizedString("bluetooth.mode.nopin", comment: "No comment provided")
		}
	}
	func protoEnumValue() -> Config.BluetoothConfig.PairingMode {
		switch self {
		case .randomPin:
			return Config.BluetoothConfig.PairingMode.randomPin
		case .fixedPin:
			return Config.BluetoothConfig.PairingMode.fixedPin
		case .noPin:
			return Config.BluetoothConfig.PairingMode.noPin
		}
	}
}
