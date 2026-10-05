//
//  AccessibilityDriver.swift
//  MeshtasticUITests
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
	/// Tap a root tab bar button. `ContentView` tags each tab with a stable
	/// `.accessibilityIdentifier("tab-*")`, but as of Xcode 26.6 / iOS 18+ that identifier does
	/// NOT propagate to the underlying `UITabBarButton` through either form of SwiftUI's
	/// value-based `Tab(value:)` API (confirmed empirically: dumping the live accessibility
	/// hierarchy during a real run shows the button with a `label:` but no `identifier:` at all,
	/// whether the identifier is set on the `Tab` itself or inside its `label: { }` closure) —
	/// this is a known SwiftUI/UIKit-bridge gap, not a bug in this app. `XCUIElementQuery`'s
	/// string subscript matches on `identifier` OR falls back to the element's accessibility
	/// label when no true identifier is present, so passing the tab's visible title ("Connect",
	/// "Messages", "Nodes", "Map", "Settings") works today. That means tab lookup is currently
	/// **locale-dependent** — capture runs in whatever locale the simulator/device is set to
	/// (English by default) — unlike `.tapIdentifier`, which is genuinely identifier-based and
	/// locale-independent. If a future SwiftUI version fixes identifier propagation for `Tab`,
	/// this can switch back to the `tab-*` identifiers already present in `ContentView` with no
	/// call-site changes needed elsewhere.
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
	/// Fixed pause. Use sparingly and only when there's no reliable "done" element to wait on
	/// (e.g. a MapKit tile load, a spring animation) — prefer `.waitForIdentifier` everywhere
	/// else, since a fixed pause is either wastefully slow or a source of flakiness depending on
	/// which side of "long enough" the runner lands on.
	case pause(TimeInterval)
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

			case .pause(let seconds):
				Thread.sleep(forTimeInterval: seconds)
			}
		}
	}
}
