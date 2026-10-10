//
//  Haptics.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/9/26.
//
import UIKit

/// Impact haptics where the platform has them. visionOS has no haptic engine, so this is a no-op there.
enum Haptics {
	enum Impact {
		case light, soft, rigid, heavy
	}

	static func impact(_ impact: Impact) {
		#if !os(visionOS)
		let style: UIImpactFeedbackGenerator.FeedbackStyle = switch impact {
		case .light: .light
		case .soft: .soft
		case .rigid: .rigid
		case .heavy: .heavy
		}
		UIImpactFeedbackGenerator(style: style).impactOccurred()
		#endif
	}
}
