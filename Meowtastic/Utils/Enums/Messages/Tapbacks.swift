import Foundation

enum Tapbacks: Int, CaseIterable, Identifiable {
	case wave = 0
	case heart = 1
	case thumbsUp = 2
	case thumbsDown = 3
	case haHa = 4
	case exclamation = 5
	case question = 6
	case poop = 7

	var id: Int {
		self.rawValue
	}

	var emojiString: String {
		switch self {
		case .wave:
			return "👋"

		case .heart:
			return "❤️"

		case .thumbsUp:
			return "👍"

		case .thumbsDown:
			return "👎"

		case .haHa:
			return "🤣"

		case .exclamation:
			return "‼️"

		case .question:
			return "❓"

		case .poop:
			return "💩"
		}
	}

	var description: String {
		switch self {
		case .wave:
			return "Wave"

		case .heart:
			return "Heart"

		case .thumbsUp:
			return "Thumbs Up"

		case .thumbsDown:
			return "Thumbs Down"

		case .haHa:
			return "Ha-Ha"

		case .exclamation:
			return "!"

		case .question:
			return "?"

		case .poop:
			return "Poop"
		}
	}
}
