import Foundation
import MeshtasticProtobufs

enum GPSMode: Int, CaseIterable, Equatable {
	case enabled = 1
	case disabled = 0
	case notPresent = 2

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .disabled:
			return "Disabled"

		case .enabled:
			return "Enabled"

		case .notPresent:
			return "Not Present"
		}
	}

	func protoEnumValue() -> Config.PositionConfig.GpsMode {
		switch self {
		case .enabled:
			return Config.PositionConfig.GpsMode.enabled

		case .disabled:
			return Config.PositionConfig.GpsMode.disabled

		case .notPresent:
			return Config.PositionConfig.GpsMode.notPresent
		}
	}
}
