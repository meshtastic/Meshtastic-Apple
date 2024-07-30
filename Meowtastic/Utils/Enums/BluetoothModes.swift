import Foundation
import MeshtasticProtobufs

enum BluetoothModes: Int, CaseIterable, Identifiable {
	case randomPin = 0
	case fixedPin = 1
	case noPin = 2

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .randomPin:
			return "bluetooth.mode.randompin".localized

		case .fixedPin:
			return "bluetooth.mode.fixedpin".localized

		case .noPin:
			return "bluetooth.mode.nopin".localized
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
