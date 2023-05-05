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
