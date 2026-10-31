//
//  DisplayInputTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import CoreGraphics
import Testing
@testable import Meshtastic

@Suite("Screen mirror input")
struct DisplayInputTests {

	@Test("Event codes match the firmware's input broker")
	func eventCodes() {
		#expect(DisplayInputEvent.select.rawValue == 10)
		#expect(DisplayInputEvent.selectLong.rawValue == 11)
		#expect(DisplayInputEvent.up.rawValue == 17)
		#expect(DisplayInputEvent.down.rawValue == 18)
		#expect(DisplayInputEvent.left.rawValue == 19)
		#expect(DisplayInputEvent.right.rawValue == 20)
		#expect(DisplayInputEvent.cancel.rawValue == 24)
		#expect(DisplayInputEvent.back.rawValue == 27)
		#expect(DisplayInputEvent.userPress.rawValue == 28)
		#expect(DisplayInputEvent.allCases.filter(\.isDirection) == [.up, .down, .left, .right])
	}

	@Test("A touch maps to the panel pixel under it")
	func panelPoint() {
		let size = CGSize(width: 640, height: 480)
		#expect(DisplayInputMapping.panelPoint(for: .zero, in: size, panelWidth: 320, panelHeight: 240) == DisplayTouchPoint(x: 0, y: 0))
		#expect(DisplayInputMapping.panelPoint(for: CGPoint(x: 321, y: 239), in: size, panelWidth: 320, panelHeight: 240) == DisplayTouchPoint(x: 160, y: 119))
	}

	@Test("A touch on or past the edge stays on the panel")
	func panelPointClamps() {
		let size = CGSize(width: 640, height: 480)
		#expect(DisplayInputMapping.panelPoint(for: CGPoint(x: 640, y: 480), in: size, panelWidth: 320, panelHeight: 240) == DisplayTouchPoint(x: 319, y: 239))
		#expect(DisplayInputMapping.panelPoint(for: CGPoint(x: -5, y: 900), in: size, panelWidth: 320, panelHeight: 240) == DisplayTouchPoint(x: 0, y: 239))
	}

	@Test("No touch point without a size")
	func panelPointNeedsSize() {
		#expect(DisplayInputMapping.panelPoint(for: .zero, in: .zero, panelWidth: 320, panelHeight: 240) == nil)
		#expect(DisplayInputMapping.panelPoint(for: .zero, in: CGSize(width: 10, height: 10), panelWidth: 0, panelHeight: 240) == nil)
	}

	@Test("Swipes send the direction they point in")
	func swipes() {
		#expect(DisplayInputMapping.swipeDirection(for: CGSize(width: 60, height: 10)) == .right)
		#expect(DisplayInputMapping.swipeDirection(for: CGSize(width: -60, height: 10)) == .left)
		#expect(DisplayInputMapping.swipeDirection(for: CGSize(width: 10, height: 60)) == .down)
		#expect(DisplayInputMapping.swipeDirection(for: CGSize(width: 10, height: -60)) == .up)
	}

	@Test("Short drags are taps, not swipes")
	func shortDrag() {
		#expect(DisplayInputMapping.swipeDirection(for: CGSize(width: 47, height: -47)) == nil)
		#expect(DisplayInputMapping.swipeDirection(for: .zero) == nil)
	}
}
