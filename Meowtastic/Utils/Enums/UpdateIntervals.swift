import Foundation

enum UpdateIntervals: Int, CaseIterable, Identifiable {
	case tenSeconds = 10
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case thirtyMinutes = 1800
	case oneHour = 3600
	case threeHours = 10800
	case sixHours = 21600
	case twelveHours = 43200
	case twentyFourHours = 86400
	case fortyeightHours = 172800

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .tenSeconds:
			return "10s"

		case .thirtySeconds:
			return "30s"

		case .oneMinute:
			return "1m"

		case .fiveMinutes:
			return "5m"

		case .tenMinutes:
			return "10m"

		case .thirtyMinutes:
			return "30m"

		case .oneHour:
			return "1h"

		case .threeHours:
			return "3h"

		case .sixHours:
			return "6h"

		case .twelveHours:
			return "12h"

		case .twentyFourHours:
			return "24h"

		case .fortyeightHours:
			return "2d"
		}
	}
}
