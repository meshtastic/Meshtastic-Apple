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
			return "tapback.wave".localized
		case .heart:
			return "tapback.heart".localized
		case .thumbsUp:
			return "tapback.thumbsup".localized
		case .thumbsDown:
			return "tapback.thumbsdown".localized
		case .haHa:
			return "tapback.haha".localized
		case .exclamation:
			return "tapback.exclamation".localized
		case .question:
			return "tapback.question".localized
		case .poop:
			return "tapback.poop".localized
		}
	}
}
