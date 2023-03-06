//
//  BluetoothModes.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/19/22.
//
import Foundation

enum BluetoothModes: Int, CaseIterable, Identifiable {

	case randomPin = 0
	case fixedPin = 1
	case noPin = 2

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .randomPin:
			return NSLocalizedString("bluetooth.mode.randompin", comment: "Random PIN")
		case .fixedPin:
			return NSLocalizedString("bluetooth.mode.fixedpin", comment: "Fixed PIN")
		case .noPin:
			return NSLocalizedString("bluetooth.mode.nopin", comment: "No PIN (Just Works)")
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
