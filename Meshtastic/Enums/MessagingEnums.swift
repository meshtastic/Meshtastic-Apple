//
//  MessagingEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/30/22.
//
import Foundation

enum BubblePosition {
	case left
	case right
}

enum Tapbacks: Int, CaseIterable, Identifiable {

	case wave = 0
	case heart = 1
	case thumbsUp = 2
	case thumbsDown = 3
	case haHa = 4
	case exclamation = 5
	case question = 6
	case poop = 7

	var id: Int { self.rawValue }
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
			return String(localized: "Wave", comment: "Tapbacks.description")
		case .heart:
			return String(localized: "Heart", comment: "Tapbacks.description")
		case .thumbsUp:
			return String(localized: "Thumbs Up", comment: "Tapbacks.description")
		case .thumbsDown:
			return String(localized: "Thumbs Down", comment: "Tapbacks.description")
		case .haHa:
			return String(localized: "HaHa", comment: "Tapbacks.description")
		case .exclamation:
			return String(localized: "Exclamation", comment: "Tapbacks.description")
		case .question:
			return String(localized: "Question", comment: "Tapbacks.description")
		case .poop:
			return String(localized: "Poop", comment: "Tapbacks.description")
		}
	}
}
