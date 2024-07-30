import Foundation
import MeshtasticProtobufs

enum GPSUpdateIntervals: Int, CaseIterable, Identifiable {
	case thirtySeconds = 30
	case oneMinute = 60
	case twoMinutes = 120
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case sixHours = 21600
	case twelveHours = 43200
	case twentyFourHours = 86400
	case maxInt32 = 2147483647

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .thirtySeconds:
			return "30s"

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

		case .sixHours:
			return "6h"

		case .twelveHours:
			return "12h"

		case .twentyFourHours:
			return "24h"

		case .maxInt32:
			return "On Boot"
		}
	}
}
