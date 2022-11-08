//
//  MessagingEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/30/22.
//

enum BubblePosition {
	case left
	case right
}

enum Tapbacks: Int, CaseIterable, Identifiable {

	case heart = 0
	case thumbsUp = 1
	case thumbsDown = 2
	case haHa = 3
	case exclamation = 4
	case question = 5
	case poop = 6

	var id: Int { self.rawValue }
	var emojiString: String {
		get {
			switch self {
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
	}
	var description: String {
		get {
			switch self {
			case .heart:
				return "Heart"
			case .thumbsUp:
				return "Thumbs Up"
			case .thumbsDown:
				return "Thumbs Down"
			case .haHa:
				return "HaHa"
			case .exclamation:
				return "Exclamation Mark"
			case .question:
				return "Question Mark"
			case .poop:
				return "Poop"
			}
		}
	}
}
