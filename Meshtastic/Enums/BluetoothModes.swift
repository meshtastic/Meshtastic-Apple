//
//  BluetoothModes.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/19/22.
//

enum BluetoothModes: Int, CaseIterable, Identifiable {

	case randomPin = 0
	case fixedPin = 1
	case noPin = 2

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .randomPin:
				return "Random PIN"
			case .fixedPin:
				return "Fixed PIN"
			case .noPin:
				return "No PIN (Just Works)"
			}
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
