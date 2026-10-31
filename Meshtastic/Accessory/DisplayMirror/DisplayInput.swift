//
//  DisplayInput.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import CoreGraphics
import Foundation

/// Button presses the radio accepts through `send_input_event`. These are the firmware's
/// input broker codes, the same ones its physical buttons produce (design#142 §5.1).
enum DisplayInputEvent: UInt32, CaseIterable {
	case select = 10
	case selectLong = 11
	case up = 17
	case down = 18
	case left = 19
	case right = 20
	case cancel = 24
	case back = 27
	case userPress = 28

	var isDirection: Bool {
		switch self {
		case .up, .down, .left, .right: return true
		default: return false
		}
	}
}

/// A panel pixel for touch events.
struct DisplayTouchPoint: Equatable {
	let x: UInt32
	let y: UInt32
}

enum DisplayInputMapping {

	/// Shorter drags than this are taps, not swipes.
	static let swipeThreshold: CGFloat = 48
	/// A press held this long is a long press.
	static let longPressDuration: TimeInterval = 0.5
	/// Hold-to-repeat: first repeat after this delay, then at `repeatInterval`. Slower than
	/// key repeat on purpose so presses can't outrun the radio's screen.
	static let repeatDelay: Duration = .milliseconds(500)
	static let repeatInterval: Duration = .milliseconds(100)

	/// Maps a point on the drawn mirror to the radio pixel under it, clamped to the panel.
	static func panelPoint(for location: CGPoint, in renderedSize: CGSize, panelWidth: Int, panelHeight: Int) -> DisplayTouchPoint? {
		guard renderedSize.width > 0, renderedSize.height > 0, panelWidth > 0, panelHeight > 0 else { return nil }
		func map(_ value: CGFloat, _ rendered: CGFloat, _ panel: Int) -> UInt32 {
			let pixel = Int((value / rendered * CGFloat(panel)).rounded(.down))
			return UInt32(min(max(pixel, 0), panel - 1))
		}
		return DisplayTouchPoint(
			x: map(location.x, renderedSize.width, panelWidth),
			y: map(location.y, renderedSize.height, panelHeight)
		)
	}

	/// The direction a drag points in, or nil when it's too short to be a swipe.
	static func swipeDirection(for translation: CGSize) -> DisplayInputEvent? {
		let dx = translation.width
		let dy = translation.height
		guard max(abs(dx), abs(dy)) >= swipeThreshold else { return nil }
		if abs(dx) > abs(dy) {
			return dx > 0 ? .right : .left
		}
		return dy > 0 ? .down : .up
	}
}
