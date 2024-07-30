import Foundation
import MeshtasticProtobufs

enum Bandwidths: Int, CaseIterable, Identifiable {
	case thirtyOne = 31
	case sixtyTwo = 62
	case oneHundredTwentyFive = 125
	case twoHundredFifty = 250
	case fiveHundred = 500

	var id: Int {
		self.rawValue
	}

	var description: String {
		switch self {
		case .thirtyOne:
			return "31 kHz"

		case .sixtyTwo:
			return "62 kHz"

		case .oneHundredTwentyFive:
			return "125 kHz"

		case .twoHundredFifty:
			return "250 kHz"

		case .fiveHundred:
			return "500 kHz"
		}
	}
}
