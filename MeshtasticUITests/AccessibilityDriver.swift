//
//  AccessibilityDriver.swift
//  MeshtasticUITests
//
//  Copyright(c) Meshtastic 2026.
//
//  A small, reusable accessibility-tree-driven navigator for the Meshtastic app: drives
//  XCUIApplication through real element queries and taps — the same path VoiceOver and a real
//  user's touches take — rather than tapping into the app's internals.
//
//  This is deliberately NOT the same mechanism as `MarketingCapture` (Meshtastic/Persistence/
//  MarketingCapture.swift), which navigates in-process via `Router` — that's fast and great for
//  App Store screenshots of a fixed, curated screen list, but it bypasses real touch dispatch,
//  hit-testing, and accessibility traits entirely. Driving through `XCUIApplication` element
//  queries instead means a passing navigation here also proves the target is actually reachable
//  and tappable through the accessibility tree, which catches a real class of regression
//  (UIKit-bridged gesture-recognizer hit-testing gaps, missing/incorrect accessibility traits)
//  that in-process navigation can't.
//

import XCTest

/// One step in an accessibility-driven navigation sequence.
enum NavigationStep {
	/// Tap a root tab bar button by its visible title. SwiftUI does not pass tab identifiers
	/// to the underlying button, so callers must pin the app language to match these titles.
	case tab(String)
	/// Tap the first element (any type — button, row, icon) matching an accessibility
	/// identifier.
	case tapIdentifier(String)
	/// Tap the first button whose accessibility label equals this text exactly. Prefer
	/// `.tapIdentifier` when the target has (or can be given) a stable identifier; this exists
	/// for elements — like system-provided buttons — that can't be identifier-tagged.
	case tapButtonLabeled(String)
	/// Wait for an element with this identifier to exist before continuing, without tapping it.
	/// Use after a navigation step whose destination needs a moment to mount, fetch, or
	/// transition in.
	case waitForIdentifier(String, timeout: TimeInterval = 5)
}

@MainActor
enum AccessibilityDriver {

	/// Runs `steps` against `app` in order. Fails the calling test (via `XCTFail`, attributed to
	/// the call site through `file`/`line`) and stops if any tap/wait target never appears —
	/// a step that can't be reached is itself a finding (a real accessibility or navigation
	/// regression), not something to silently skip past.
	static func run(
		_ steps: [NavigationStep],
		app: XCUIApplication,
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		for step in steps {
			switch step {
			case .tab(let identifier):
				let button = app.tabBars.buttons[identifier]
				guard button.waitForExistence(timeout: 5) else {
					XCTFail("Tab '\(identifier)' never appeared", file: file, line: line)
					return
				}
				button.tap()

			case .tapIdentifier(let identifier):
				let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
				guard element.waitForExistence(timeout: 5) else {
					XCTFail("Element '\(identifier)' never appeared", file: file, line: line)
					return
				}
				element.tap()

			case .tapButtonLabeled(let label):
				let button = app.buttons[label]
				guard button.waitForExistence(timeout: 5) else {
					XCTFail("Button labeled '\(label)' never appeared", file: file, line: line)
					return
				}
				button.tap()

			case .waitForIdentifier(let identifier, let timeout):
				let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
				if !element.waitForExistence(timeout: timeout) {
					XCTFail("Element '\(identifier)' never appeared within \(timeout)s", file: file, line: line)
					return
				}
			}
		}
	}
}
