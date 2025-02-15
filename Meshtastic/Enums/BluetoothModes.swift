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
			return "Random Pin".localized
		case .fixedPin:
			return "Fixed Pin".localized
		case .noPin:
			return "No PIN (Just Works)".localized
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
