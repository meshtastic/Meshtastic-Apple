import Foundation
import MeshtasticProtobufs

enum ScreenOnIntervals: Int, CaseIterable, Identifiable {
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case max = 31536000 // One Year

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .fifteenSeconds:
			return "15s"

		case .thirtySeconds:
			return "30s"

		case .oneMinute:
			return "1m"

		case .fiveMinutes:
			return "5m"

		case .tenMinutes:
			return "10m"

		case .fifteenMinutes:
			return "15m"

		case .thirtyMinutes:
			return "30m"

		case .oneHour:
			return "1h"

		case .max:
			return "Always On"
		}
	}
}
