import Foundation
import MeshtasticProtobufs

// Default of 0 is auto
enum OLEDTypes: Int, CaseIterable, Identifiable {
	case auto = 0
	case ssd1306 = 1
	case sh1106 = 2
	case sh1107 = 3

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .auto:
			return "Auto"

		case .ssd1306:
			return "SSD 1306"

		case .sh1106:
			return "SH 1106"

		case .sh1107:
			return "SH 1107"
		}
	}

	func protoEnumValue() -> Config.DisplayConfig.OledType {
		switch self {
		case .auto:
			return Config.DisplayConfig.OledType.oledAuto

		case .ssd1306:
			return Config.DisplayConfig.OledType.oledSsd1306

		case .sh1106:
			return Config.DisplayConfig.OledType.oledSh1106

		case .sh1107:
			return Config.DisplayConfig.OledType.oledSh1107
		}
	}
}
