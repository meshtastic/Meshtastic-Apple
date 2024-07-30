import Foundation

enum UpdateIntervals: Int, CaseIterable, Identifiable {
	case tenSeconds = 10
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case fortyFiveSeconds = 45
	case oneMinute = 60
	case twoMinutes = 120
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case twoHours = 7200
	case threeHours = 10800
	case fourHours = 14400
	case fiveHours = 18000
	case sixHours = 21600
	case twelveHours = 43200
	case eighteenHours = 64800
	case twentyFourHours = 86400
	case thirtySixHours = 129600
	case fortyeightHours = 172800
	case seventyTwoHours = 259200

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .tenSeconds:
			return "10s"

		case .fifteenSeconds:
			return "15s"

		case .thirtySeconds:
			return "30s"

		case .fortyFiveSeconds:
			return "45s"

		case .oneMinute:
			return "1m"

		case .twoMinutes:
			return "2m"

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

		case .twoHours:
			return "2h"

		case .threeHours:
			return "3h"

		case .fourHours:
			return "4h"

		case .fiveHours:
			return "5h"

		case .sixHours:
			return "6h"

		case .twelveHours:
			return "12h"

		case .eighteenHours:
			return "18h"

		case .twentyFourHours:
			return "24h"

		case .thirtySixHours:
			return "36h"

		case .fortyeightHours:
			return "2d"

		case .seventyTwoHours:
			return "3d"
		}
	}
}
