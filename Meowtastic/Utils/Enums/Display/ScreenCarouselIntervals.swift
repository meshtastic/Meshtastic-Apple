import Foundation

// Default of 0 is off
enum ScreenCarouselIntervals: Int, CaseIterable, Identifiable {
	case off = 0
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .off:
			return "Off"

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
		}
	}
}
