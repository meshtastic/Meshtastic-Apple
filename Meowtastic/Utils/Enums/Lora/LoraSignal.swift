import Foundation

enum LoraSignal: Int {
	case none = 0
	case bad = 1
	case fair = 2
	case good = 3

	var description: String {
		switch self {
		case .none:
			return "None"
		case .bad:
			return "Bad"
		case .fair:
			return "Fair"
		case .good:
			return "Good"
		}
	}
}
