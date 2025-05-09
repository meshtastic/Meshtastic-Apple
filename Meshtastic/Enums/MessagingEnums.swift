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
			return "Wave".localized
		case .heart:
			return "Heart".localized
		case .thumbsUp:
			return "Thumbs Up".localized
		case .thumbsDown:
			return "Thumbs Down".localized
		case .haHa:
			return "HaHa".localized
		case .exclamation:
			return "Exclamation".localized
		case .question:
			return "Question".localized
		case .poop:
			return "Poop".localized
		}
	}
}
