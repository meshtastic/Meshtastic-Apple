import XCTest

final class MigrationBootstrapAccessibilityTests: XCTestCase {
	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	@MainActor
	func testMigratingScreenAccessibility() throws {
		let app = XCUIApplication()
		app.launchArguments = ["--migration-bootstrap-preview"]
		app.launch()

		let title = app.staticTexts["migration-bootstrap-title"]
		XCTAssertTrue(title.waitForExistence(timeout: 5))
		XCTAssertEqual(title.label, "Updating local data…")

		XCTAssertFalse(app.descendants(matching: .any)["migration-bootstrap-progress"].exists)

		let instruction = app.staticTexts["migration-bootstrap-instruction"]
		XCTAssertTrue(instruction.exists)
		XCTAssertEqual(
			instruction.label,
			"This may take a minute. Keep Meshtastic open while local data is updated"
		)

		try app.performAccessibilityAudit()
	}

	@MainActor
	func testFailureScreenAccessibility() throws {
		let app = XCUIApplication()
		app.launchArguments = ["--migration-bootstrap-preview-failed"]
		app.launch()

		let title = app.staticTexts["migration-bootstrap-title"]
		XCTAssertTrue(title.waitForExistence(timeout: 5))
		XCTAssertEqual(title.label, "Local data update failed")
		XCTAssertTrue(app.staticTexts["Test migration error"].exists)

		let retryButton = app.buttons["migration-bootstrap-retry"]
		XCTAssertTrue(retryButton.exists)
		XCTAssertTrue(retryButton.isEnabled)
		XCTAssertEqual(retryButton.label, "Retry")

		try app.performAccessibilityAudit()
	}
}
