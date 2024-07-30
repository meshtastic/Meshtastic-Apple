import Foundation
import MeshtasticProtobufs

// Default of 0 is metric
enum Units: Int, CaseIterable, Identifiable {
	case metric = 0
	case imperial = 1

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .metric:
			return "Metric"

		case .imperial:
			return "Imperial"
		}
	}

	func protoEnumValue() -> Config.DisplayConfig.DisplayUnits {
		switch self {
		case .metric:
			return Config.DisplayConfig.DisplayUnits.metric

		case .imperial:
			return Config.DisplayConfig.DisplayUnits.imperial
		}
	}
}
