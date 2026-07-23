//
//  TabBarNavigationUITests.swift
//  MeshtasticUITests
//
//  Regression coverage for the root tab bar: every tab must actually be reachable through the
//  accessibility tree (the same path VoiceOver and a real user's tap take). Also doubles as the
//  first real exercise of AccessibilityDriver — if a future change breaks TabView (removes a
//  tab, changes its title without updating this list, or reintroduces a hit-testing regression),
//  this fails loudly instead of silently.
//

import XCTest

final class TabBarNavigationUITests: XCTestCase {

	override func setUpWithError() throws {
		// A tab that never appears is the finding — stop immediately rather than limping
		// through the remaining tabs against a bar the driver never actually reached.
		continueAfterFailure = false
	}

	@MainActor
	func testAllRootTabsAreReachable() {
		let app = XCUIApplication()
		// Skips onboarding/tips and disables BLE discovery/autoconnect so tab switches aren't
		// racing a connect attempt or blocked behind a first-launch sheet — see
		// Meshtastic/Persistence/PerformanceSeedData.swift.
		// Pin the locale so NavigationStep.tab's title-based lookup (see AccessibilityDriver.swift)
		// doesn't flake when the simulator/device isn't running in English.
		app.launchArguments += [
			"--meshtastic-marketing-seed",
			"-AppleLanguages", "(en)",
			"-AppleLocale", "en_US"
		]
		app.launch()

		// English titles: see NavigationStep.tab's doc comment for why tab lookup currently
		// matches on the visible label rather than the tab-* accessibilityIdentifier already
		// set on each tab in ContentView.swift.
		for title in ["Messages", "Nodes", "Map", "Settings", "Connect"] {
			AccessibilityDriver.run([.tab(title)], app: app)
		}
	}
}
