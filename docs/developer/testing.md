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

Select the `Meshtastic` scheme and run with ⌘U in Xcode, or use `xcodebuild test -scheme Meshtastic`.
This runs `MeshtasticTests`, not the opt-in UI tests described below.

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
`tapButtonLabeled`, `waitForIdentifier`) and a `run(_:app:)` that fails the calling test
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
            "--meshtastic-marketing-seed",  // replaces the app store with demo data
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        AccessibilityDriver.run([.tab("Connect")], app: app)
    }
}
```

`NavigationStep.tab` matches the visible tab title because SwiftUI does not pass tab identifiers
to the underlying button. Pin the app language to match those titles, as shown above.
`.tapIdentifier` uses stable identifiers and does not depend on the app language.

### Running UI Tests

UI tests are opt-in. Select the `Meshtastic UI Tests` scheme and a disposable simulator, then
press ⌘U. The normal `Meshtastic` scheme does not include this test target.

**The marketing seed launch argument replaces the app's stored data with demo data.** Do not run
these tests on a simulator or device whose Meshtastic data you want to keep.

```bash
xcodebuild -project Meshtastic.xcodeproj -scheme "Meshtastic UI Tests" \
  -destination 'platform=iOS Simulator,name=<disposable-simulator>' \
  -only-testing:MeshtasticUITests/TabBarNavigationUITests test
```

These UI tests do not run in CI. `.github/workflows/unit-tests.yml` runs only `MeshtasticTests`.

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
