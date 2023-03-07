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

	case heart = 0
	case thumbsUp = 1
	case thumbsDown = 2
	case haHa = 3
	case exclamation = 4
	case question = 5
	case poop = 6

	var id: Int { self.rawValue }
	var emojiString: String {
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
	var description: String {
		switch self {
		case .heart:
			return NSLocalizedString("tapback.heart", comment: "Heart")
		case .thumbsUp:
			return NSLocalizedString("tapback.thumbsup", comment: "Thumbs Up")
		case .thumbsDown:
			return NSLocalizedString("tapback.thumbsdown", comment: "Thumbs Down")
		case .haHa:
			return NSLocalizedString("tapback.haha", comment: "HaHa")
		case .exclamation:
			return NSLocalizedString("tapback.exclamation", comment: "Exclamation Mark")
		case .question:
			return NSLocalizedString("tapback.question", comment: "Question Mark")
		case .poop:
			return NSLocalizedString("tapback.poop", comment: "Poop")
		}
	}
}
