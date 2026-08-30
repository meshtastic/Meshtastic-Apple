//
//  AccessibilityTests.swift
//  Meshtastic TVUITests
//

import XCTest

@MainActor
final class AccessibilityTests: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	func testConnectionScreenPassesAccessibilityAudit() throws {
		let app = XCUIApplication()
		app.launch()

		XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
		try app.performAccessibilityAudit()
	}

	func testSettingsStartsWithMapTypeFocused() {
		let app = XCUIApplication()
		app.launchArguments = ["-tv-show-settings"]
		app.launch()

		let mapType = app.descendants(matching: .any)["settings.mapType"]
		XCTAssertTrue(mapType.waitForExistence(timeout: 5))
		let mapTypeOptions = ["Standard", "Hybrid", "Satellite"].map { app.buttons[$0] }
		XCTAssertTrue(waitForFocus(in: mapTypeOptions, timeout: 5))
		XCTAssertFalse(app.buttons["settings.clearNodeDatabase"].hasFocus)
	}

	private func waitForFocus(in elements: [XCUIElement], timeout: TimeInterval) -> Bool {
		let predicate = NSPredicate { _, _ in elements.contains(where: \.hasFocus) }
		let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
		return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
	}
}
