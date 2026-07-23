---
title: Testing
parent: Developer Guide
nav_order: 6
---

# Testing

The test target is `MeshtasticTests/`. All new tests must use **Swift Testing** (`import Testing`).

## Writing Tests

```swift
import Testing
@testable import Meshtastic

@Suite("MyFeatureTests")
struct MyFeatureTests {

    @Test func someExpectation() {
        let value = computeSomething()
        #expect(value == 42)
    }

    @Test func requiredValue() throws {
        let result = try #require(optionalValue())
        #expect(result.count > 0)
    }
}
```

- Use `@Suite` to group related tests under a descriptive name.
- Use `#expect` for assertions (does not throw on failure — test continues).
- Use `#require` for preconditions (throws on failure — test stops).
- Do not use `XCTAssert*` in new test files.

## Running Tests

Run with ⌘U in Xcode, or from the command line with `xcodebuild test` — see "Running UI Tests"
below for the exact invocation `MeshtasticUITests` uses.

Ensure all existing tests pass before opening a PR. SwiftLint runs on every commit; tests failing due to lint errors will block CI.

## Snapshot Tests

Snapshot tests for SwiftUI views live in `MeshtasticTests/SwiftUIViewSnapshotTests.swift`.

### How Snapshots Work

1. A `renderImage` helper renders a SwiftUI view to a `UIImage` using `UIHostingController` + `drawHierarchy(in:afterScreenUpdates:true)`.
2. On first run, the PNG is saved as a reference. Snapshots with `forDocs: true` are saved to `docs/assets/screenshots/` (shared with the documentation site); test-only snapshots are saved to `MeshtasticTests/__Snapshots__/`.
3. On subsequent runs, the rendered image is compared pixel-by-pixel to the reference using `CGImage` dimensions.
4. `copy-snapshots.sh` copies only doc-referenced PNGs into the app bundle — test-only snapshots are never bundled.

### Writing a Snapshot Test

```swift
@Suite("MyViewSnapshotTests")
struct MyViewSnapshotTests {

    @Test func rendersCorrectly() throws {
        let image = try renderImage(MyView(), width: 390)
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == 390 * Int(UIScreen.main.scale))
    }
}
```

- Name suites `<ViewName>SnapshotTests`.
- Compare using `cgImage.width` / `cgImage.height` (pixel dimensions at screen scale), not `UIImage.size` (which is scale-dependent).
- For views with `ScrollView` or no intrinsic height, pass an explicit `height:` parameter to `renderImage`.
- Commit reference PNGs alongside the test file.

### Embedding Dark/Light Snapshot Pairs in Docs

When a view is snapshotted in both color schemes (e.g. `foo_light.png` + `foo_dark.png`), embedding both `![]()` tags side-by-side causes both images to appear simultaneously on the Jekyll site and in the in-app viewer. Use an HTML `<picture>` element instead:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/screenshots/foo_dark.png" />
  <img src="../assets/screenshots/foo_light.png" alt="Description" />
</picture>
```

This works in both contexts because `build-docs.sh` invokes `cmark-gfm --unsafe` (raw HTML is passed through) and `WKWebView` (used for in-app display) is full WebKit and respects `prefers-color-scheme`.

### Regenerating Snapshots

Delete the reference PNG and run the test once — it records a new reference. Commit the new reference with your PR.

## UI Tests (MeshtasticUITests)

`MeshtasticUITests/` is a separate target from `MeshtasticTests/` for accessibility-tree-driven
UI automation — driving the app through real `XCUIApplication` element queries and taps, the
same path VoiceOver and a real user's touches take. This is deliberately **not** the same
mechanism as `MarketingCapture` (`Meshtastic/Persistence/MarketingCapture.swift`), which
navigates in-process via `Router` for fast, curated App Store screenshots but bypasses real touch
dispatch, hit-testing, and accessibility traits entirely — a UI test here proves the target is
actually reachable and tappable through the accessibility tree, catching a class of regression
(broken hit-testing, missing/incorrect accessibility traits) in-process navigation can't.

**XCUITest requires `XCTestCase`, not Swift Testing.** Unlike `MeshtasticTests`, files in
`MeshtasticUITests/` use `XCTestCase`/`XCTFail`/`continueAfterFailure` — this is a deliberate,
necessary exception to the "no `XCTAssert*` in new test files" rule above, not a drift from it;
Swift Testing has no UI-automation equivalent to `XCUIApplication`.

### AccessibilityDriver

`AccessibilityDriver.swift` provides `NavigationStep` (`tab`, `tapIdentifier`,
`tapButtonLabeled`, `waitForIdentifier`, `pause`) and a `run(_:app:)` that fails the calling test
immediately — not silently — when a step's target never appears, since an unreachable target is
itself the finding:

```swift
import XCTest

final class MyFeatureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSomeFlowIsReachable() {
        let app = XCUIApplication()
        // Pin the locale so tab-title matching in AccessibilityDriver (see the note below)
        // doesn't flake on a non-English simulator/device.
        app.launchArguments += [
            "--meshtastic-marketing-seed",  // skip onboarding, seed demo data
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        AccessibilityDriver.run([.tab("Connect")], app: app)
    }
}
```

Note on tab lookup: `ContentView` tags each root tab bar button with a stable
`.accessibilityIdentifier("tab-*")`, but as of Xcode 26.6 / iOS 18+ that identifier does not
propagate to the underlying `UITabBarButton` through SwiftUI's value-based `Tab(value:)` API
(confirmed by dumping the live accessibility hierarchy during a real run — the button exposes a
`label:` but no `identifier:` at all). `NavigationStep.tab` therefore matches on the visible
title as a working fallback, which means tab lookup is currently locale-dependent — unlike
`.tapIdentifier`, which is genuinely identifier-based and locale-independent. See the doc comment
on `NavigationStep.tab` for the full story.

### Running UI Tests

```bash
xcodebuild -project Meshtastic.xcodeproj -scheme Meshtastic \
  -destination 'platform=iOS Simulator,name=<device>' \
  -only-testing:MeshtasticUITests/<SuiteName> test
```

⌘U also runs them from Xcode alongside `MeshtasticTests`, since both are wired into the
`Meshtastic` scheme's test action.

## Async Tests

For tests involving `async/await`:

```swift
@Test func asyncOperation() async throws {
    let result = await someAsyncFunction()
    #expect(result != nil)
}
```

Router is `@MainActor`; access it in tests with `await MainActor.run { }`:

```swift
@Test func routerNavigates() async {
    let router = await MainActor.run { Router() }
    await MainActor.run { router.routeSettings(path: "helpDocs") }
    let state = await MainActor.run { router.navigationState.settingsNavigationState }
    #expect(state == .helpDocs)
}
```
