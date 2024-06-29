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
			return NSLocalizedString("tapback.wave", comment: "No comment provided")
		case .heart:
			return NSLocalizedString("tapback.heart", comment: "No comment provided")
		case .thumbsUp:
			return NSLocalizedString("tapback.thumbsup", comment: "No comment provided")
		case .thumbsDown:
			return NSLocalizedString("tapback.thumbsdown", comment: "No comment provided")
		case .haHa:
			return NSLocalizedString("tapback.haha", comment: "No comment provided")
		case .exclamation:
			return NSLocalizedString("tapback.exclamation", comment: "No comment provided")
		case .question:
			return NSLocalizedString("tapback.question", comment: "No comment provided")
		case .poop:
			return NSLocalizedString("tapback.poop", comment: "No comment provided")
		}
	}
}
