---
name: ios-marketing-capture
description: Use when the user wants to automate capture of marketing screenshots for a SwiftUI iOS app across multiple locales, devices, or appearances. Covers full-screen shots, isolated element renders (carousel cards, widgets), and reproducible output naming. Triggers on marketing screenshots, locale screenshots, widget renders, App Store assets, fastlane-alternative, simctl screenshots.
---

# iOS Marketing Capture

## Overview

Automate reproducible marketing screenshot capture for a SwiftUI iOS app across multiple locales, with two parallel output streams:

1. **Full-screen captures** — every marketing-relevant screen, with deterministic seeded data, real status bar / safe-area chrome
2. **Element captures** — isolated renders of specific components (cards, widgets, charts) at any scale, with natural background inside rounded corners and transparency outside

This skill is the **capture** step. If the user also wants Apple-style marketing pages composited around the shots (device mockups, headlines, gradients), combine with the `app-store-screenshots` skill as a post-processing step.

## Core Approach

**In-app capture mode**, not XCUITest. This is a hard decision that trades off against Fastlane snapshot / XCUITest conventions, and it wins for almost every real project.

Why in-app over XCUITest:

- **No new test target.** Adding a UI test target to an existing Xcode project is fragile pbxproj surgery. Many projects have zero test targets and no xcodegen — adding one by hand is error-prone.
- **Faster iteration.** A UI test takes 30s+ to launch per run. In-app capture is just a relaunch of the installed binary.
- **No `xcodebuild test`.** The whole flow is `xcodebuild build` once, then `simctl launch` per locale. No test-bundle overhead.
- **Access to real app state.** You can call ViewModels, SwiftData, ImageRenderer, and `UIWindow.drawHierarchy` directly. XCUITest can only tap and read accessibility elements.
- **Element renders need in-process anyway.** `ImageRenderer` on widget views or isolated components must run inside the app process — there's no XCUITest equivalent.

How it works:

1. A DEBUG-only `MarketingCapture.swift` file lives in the main app target
2. When launched with `-MarketingCapture 1`, the app seeds data, then a coordinator walks a list of `CaptureStep`s — each step navigates, waits for settle, snapshots, and cleans up
3. PNGs are written to the app's sandbox `Documents/marketing/<locale>/` directory
4. A shell script builds once, installs, then loops locales by relaunching with `-AppleLanguages (xx) -AppleLocale xx`, pulling files out via `simctl get_app_container`

## Process

Work through these steps in order. Do not skip ahead.

### Step 1: Gather requirements

Ask the user these questions **one at a time** (do not batch them — each answer can invalidate later questions):

1. **Screens to capture** — "Which screens do you want? Give me the navigation path or the tab name for each." Get a concrete list, not "the main flows".
2. **Isolated elements** — "Any components you want rendered independently with transparent backgrounds? (carousel cards, widgets, hero tiles, charts, etc.)"
3. **Locales** — "Which locales? (a) all locales in your `Localizable.xcstrings`, (b) an App Store subset I'll specify, or (c) let me give you an explicit list." If (a), grep the `.xcstrings` file for locale codes:
   ```bash
   python3 -c "import json; d=json.load(open('<path>/Localizable.xcstrings')); langs=set(); [langs.update(v.get('localizations',{}).keys()) for v in d['strings'].values()]; print(sorted(langs))"
   ```
4. **Device** — "Which simulator? (6.1\" iPhone 17 recommended for iOS 26 design features)" — verify the device is available via `xcrun simctl list devices available`.
5. **Appearance** — "Light only, dark only, or both?"
6. **Seed data** — "How is demo data populated today? (a) fresh install seeds it automatically, (b) there's a debug 'Load Demo Data' button, (c) you add it manually, (d) no demo data exists yet." Then: "Is the existing data exhaustive enough that every screen you listed looks populated for marketing? Audit it with the user."

### Step 2: Exploration

Before writing any code, explore the codebase enough to answer:

- Does the project use **Xcode synchronized folder groups** (Xcode 16+, `PBXFileSystemSynchronizedRootGroup`)? If yes, new files auto-include in their target — no pbxproj edits needed. Check with `grep -c PBXFileSystemSynchronized <proj>.xcodeproj/project.pbxproj`.
- **What is the root navigation pattern?**
  - `TabView(selection:)` — most common. You need: the `@State selectedTab` binding, tab indices, and which tabs have nested `NavigationStack`.
  - `NavigationStack` (single stack with a router) — you need: the path binding or router object, plus the set of `NavigationLink(value:)` / `.navigationDestination` types.
  - `NavigationSplitView` — you need: the sidebar selection binding, detail column's navigation state.
  - Custom coordinator / UIKit host — you need: the coordinator's `navigate(to:)` method or equivalent.
- How are **deep links** routed? Find the `onOpenURL` handler and the enum/switch that maps URLs to navigation state.
- Where are **demo data seeders** defined? Trace the code path from the debug button (if any) to the function that actually writes to `ModelContext`. If no seeder exists, see "Creating a demo data seeder" below.
- Do **widgets** live in a separate target? Are the widget view files and entry types in the main app target too? (Almost certainly no — they need to be added if you want to render them via ImageRenderer.)
- Does the app use **Live Activities** / ActivityKit? If yes, flag this as a known gotcha (see below).
- Does the app use **SwiftData + CloudKit sync** (`cloudKitDatabase: .automatic`)? If yes, flag as a known gotcha.
- Does any view need to be **captured in a non-default state**? (e.g. a timer mid-countdown, a form partially filled, a chart with specific values). If yes, each needs a `static var` priming mechanism (see "Priming view state" below).

### Step 3: Present design to user

Before writing code, summarize your plan in this structure. Get explicit approval before proceeding:

1. Architecture (in-app capture mode, single file, DEBUG-gated)
2. File list (exact paths you'll create / modify)
3. Screen-by-screen capture plan (how each screen is reached — tab index, navigation path, sheet trigger)
4. Capture ordering rationale (which screens must come before others — see gotcha #5)
5. Element rendering approach (which components, how they'll be wrapped)
6. Output layout (folder structure, naming convention)
7. Known gotchas relevant to this project (flagged from Step 2)
8. Primed states needed (which views, what static vars)

### Step 4: Implement

Use the templates in `templates/` as starting points. They are **reference patterns**, not copy-paste scaffolding — every project has different navigation, models, and views. The templates show the building blocks; you compose them for the target app.

Key files to produce:

- `<AppName>/Debug/MarketingCapture.swift` — the whole capture system, DEBUG-only. Contains:
  - `MarketingCapture` enum (launch arg parsing, output helpers, window snapshot, priming vars)
  - `MarketingCaptureCoordinator` class (walks `[CaptureStep]` and snapshots each)
  - `MarketingElementHarness` enum (ImageRenderer renders of cards, widgets, charts)
- `<AppName>/ContentView.swift` (or wherever the root view lives) — DEBUG hook that seeds data and runs the coordinator.
- Any views that need primed states — DEBUG-gated `.onAppear` hooks and `.onReceive` dismiss listeners.
- `scripts/capture-marketing.sh` — build + install + per-locale loop.
- `.gitignore` — add `marketing/`.

### Step 5: Verify iteratively

Do **not** hand the script to the user and wait. Run it yourself against a simulator and verify at least one locale before declaring done. Read the output PNGs with the Read tool to visually verify each screen shows what you expect. Common runtime issues are listed in "Known Gotchas" below.

When you find an issue, fix it, rerun the whole script (not just the failing locale — fixes can regress earlier locales), and re-verify visually.

## Architecture: Step-Based Capture

The coordinator drives capture by walking a list of `CaptureStep` values. Each step is self-contained: it knows how to navigate to its screen, how long to wait, and how to clean up afterward.

```swift
struct CaptureStep {
    let name: String                        // output filename, e.g. "01-home"
    let navigate: @MainActor () -> Void     // put the app in the right state
    let settle: Duration                    // wait for animations/loads
    let cleanup: (@MainActor () -> Void)?   // tear down before next step
}
```

The coordinator is a simple loop:

```swift
for step in steps {
    step.navigate()
    try? await Task.sleep(for: step.settle)
    if let image = MarketingCapture.snapshotKeyWindow() {
        MarketingCapture.writePNG(image, name: step.name)
    }
    step.cleanup?()
    try? await Task.sleep(for: .milliseconds(400))  // cleanup animation
}
```

### Building steps for different navigation patterns

**TabView app** (most common):
```swift
// Simple tab switch — just set the index
CaptureStep(name: "01-home", navigate: { setTab(0) }, settle: .milliseconds(1800), cleanup: nil)

// Tab + presented sheet
CaptureStep(
    name: "05-timer-setup",
    navigate: {
        setTab(3)
        pendingBrewRecipe = someRecipe
    },
    settle: .milliseconds(2000),
    cleanup: {
        NotificationCenter.default.post(name: MarketingCapture.dismissSheetNotification, object: nil)
        pendingBrewRecipe = nil
    }
)
```

**NavigationStack + router app:**
```swift
// Push a route onto the stack
CaptureStep(
    name: "02-detail",
    navigate: { router.push(.itemDetail(item)) },
    settle: .milliseconds(1800),
    cleanup: { router.popToRoot() }
)
```

**NavigationSplitView app:**
```swift
// Select sidebar item, then detail
CaptureStep(
    name: "03-detail",
    navigate: {
        sidebarSelection = .recipes
        detailSelection = recipes.first
    },
    settle: .milliseconds(1800),
    cleanup: { detailSelection = nil }
)
```

### Ordering: the stacking rule

**Capture any screen that needs a "clean" navigation state BEFORE screens that push onto the same stack.** Nested `NavigationPath` / `@State` inside child views can't be popped from the coordinator. So:

```
Good:  Shelf (clean list) → Coffee Detail (pushes onto shelf's stack)
Bad:   Coffee Detail → Shelf (stack still has detail pushed)
```

If two screens share a NavigationStack, capture the root-level view first.

## Priming View State

Some screens need to be captured in a specific non-default state — a timer mid-countdown, a chart with particular values, a form half-filled. The pattern:

1. Add a `static var` to `MarketingCapture` for each priming value:
   ```swift
   /// Set by the coordinator before presenting the timer view.
   /// The view reads this in .onAppear to jump to a specific elapsed time.
   static var pendingElapsedSeconds: Int?

   /// Set to true to show the assessment overlay on the timer.
   static var pendingShowAssessment: Bool = false
   ```

2. In the target view, add a DEBUG-gated `.onAppear` that reads the priming value:
   ```swift
   .onAppear {
       #if DEBUG
       if MarketingCapture.isActive, let elapsed = MarketingCapture.pendingElapsedSeconds {
           phase = .active
           timerVM.elapsedTime = TimeInterval(elapsed)
           timerVM.start()
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { timerVM.pause() }
       }
       #endif
   }
   ```

3. In the coordinator, set the var before navigating:
   ```swift
   CaptureStep(
       name: "06-timer-midway",
       navigate: {
           MarketingCapture.pendingElapsedSeconds = 75
           openTimerSheet(someRecipe)
       },
       settle: .milliseconds(2400),
       cleanup: {
           MarketingCapture.pendingElapsedSeconds = nil
           NotificationCenter.default.post(name: MarketingCapture.dismissSheetNotification, object: nil)
       }
   )
   ```

## Creating a Demo Data Seeder

If the app has no existing demo data mechanism, create one. Place it in `<AppName>/Debug/DemoDataSeeder.swift`, wrapped in `#if DEBUG`.

Guidelines:
- Seed **enough data that every captured screen looks populated**. Audit the screen list against the seed.
- Use realistic content: real place names, plausible numbers, varied states (some items "running low", some "fresh", some with images, some without).
- If the app uses SwiftData, write directly to the `ModelContext`. If Core Data, use the managed object context. If a REST backend, seed via the local cache/store layer.
- Make seeding **idempotent** — check if data already exists before inserting. The store persists across simulator relaunches, and re-seeding per locale causes CloudKit sync churn and crashes.
- Include enough variety to fill different UI states: empty states should NOT appear unless they're a marketing screen.

Minimal shape:
```swift
#if DEBUG
enum DemoDataSeeder {
    static func seedIfEmpty(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        guard existing == 0 else { return }

        // Items with varied states
        let items = [
            Item(name: "...", status: .active, ...),
            Item(name: "...", status: .lowStock, ...),
            // ...enough to fill every screen
        ]
        items.forEach { context.insert($0) }
        try? context.save()
    }
}
#endif
```

## Element Rendering

Elements are rendered via `ImageRenderer` at 3x scale with transparency outside rounded corners.

### Cards / list rows

```swift
@MainActor
static func renderCards(items: [Item], theme: AppTheme) {
    let cardWidth: CGFloat = 380

    for item in items {
        let card = ItemCard(item: item, theme: theme)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: cardWidth)
            .background(theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = false
        renderer.proposedSize = .init(width: cardWidth, height: nil)

        guard let image = renderer.uiImage else { continue }
        MarketingCapture.writePNG(image, name: "card-\(slugify(item.name))", subfolder: "elements")
    }
}
```

### Widgets

Widget views require special handling because they normally run inside WidgetKit's process and rely on system-provided padding and backgrounds.

```swift
@MainActor
static func renderWidget(
    name: String,
    size: CGSize,
    cornerRadius: CGFloat? = nil,
    @ViewBuilder content: () -> some View
) {
    let isAccessory = size.height <= 80
    let radius = cornerRadius ?? (isAccessory ? 8 : 22)
    let contentPadding: CGFloat = isAccessory ? 0 : 16

    let view = content()
        .padding(contentPadding)
        .frame(width: size.width, height: size.height)
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .environment(\.colorScheme, .light)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 3
    renderer.isOpaque = false
    renderer.proposedSize = .init(width: size.width, height: size.height)

    guard let image = renderer.uiImage else { return }
    MarketingCapture.writePNG(image, name: name, subfolder: "elements")
}

// Standard iPhone widget sizes (points, iPhone 14-17 size class)
enum WidgetSize {
    static let small  = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large  = CGSize(width: 364, height: 382)
    static let accessoryCircular    = CGSize(width: 76, height: 76)
    static let accessoryRectangular = CGSize(width: 172, height: 76)
    static let accessoryInline      = CGSize(width: 257, height: 26)
}

// Usage:
renderWidget(name: "widget-pulse-small", size: WidgetSize.small) {
    PulseSmallView(entry: PulseEntry(
        date: Date(),
        count: 2,
        streak: 5,
        lastItemName: "Morning Routine"
    ))
}
```

### Charts / standalone views

Any SwiftUI view can be rendered as an element. Wrap it the same way — explicit size, background, corner clip:

```swift
@MainActor
static func renderChart() {
    let chart = MyChartView(values: ChartData.sample)
        .frame(width: 420, height: 420)
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

    let renderer = ImageRenderer(content: chart)
    renderer.scale = 3
    renderer.isOpaque = false
    renderer.proposedSize = .init(width: 420, height: 420)

    guard let image = renderer.uiImage else { return }
    MarketingCapture.writePNG(image, name: "chart-overview", subfolder: "elements")
}
```

## Known Gotchas

These are all real bugs that bit a real project. Treat this list as load-bearing.

### 1. Live Activities persist across app launches

ActivityKit Live Activities **outlive process termination**. If your app starts a Live Activity during capture (e.g. via a timer's `start()`), then the next locale's relaunch will inherit it. Combined with a fresh seed that deletes the models the stale LA references, you get SwiftData persisted-property assertions.

Fix: call `<ActivityManager>.shared.endImmediately()` at the very start of the marketing capture block, before touching data. Also call `timerVM.stop()` (or whatever properly ends the LA) in the view's `onDisappear` when in capture mode.

### 2. Don't re-seed on every locale

Seeding SwiftData + CloudKit per locale causes sync churn and crashes. The SwiftData store persists across relaunches — the data is locale-agnostic demo content, so seed **once** on the first run and skip subsequent runs:

```swift
contentVM.fetchItems()
if contentVM.allItems.isEmpty {
    DemoDataSeeder.seedIfEmpty(in: modelContext)
    contentVM.fetchItems()
}
```

### 3. ViewModels that setup before the seed hold stale snapshots

If the root view's `onAppear` calls `someVM.setup(modelContext:)` **before** the marketing seed runs, the VM holds a snapshot of the empty store. After seeding, call `someVM.refresh()` (or its equivalent fetch method) for every VM whose data you need.

### 4. Setting a trigger binding to nil does NOT dismiss a sheet

If a parent view presents a `.fullScreenCover(item: $request)` and `request` is driven by an internal `@State`, then setting the *trigger* binding (e.g. `pendingItem = nil`) does nothing to the cover. The cover stays up, and your next screenshot captures it instead of the screen you navigated to.

Fix: broadcast a dismiss signal via NotificationCenter, and have the presented view listen:

```swift
// MarketingCapture.swift
static let dismissSheetNotification = Notification.Name("MarketingCapture.dismissSheet")

// In presented view body
.onReceive(NotificationCenter.default.publisher(for: MarketingCapture.dismissSheetNotification)) { _ in
    dismiss()
}
```

Then in the step's `cleanup`, post the notification and allow **at least 900ms** for the cover animation to complete before the next step begins.

### 5. NavigationPath can't be popped from outside

If a child view holds `@State private var navigationPath = NavigationPath()` and a deep link pushes onto it, the coordinator can't reach in to pop. Solution: **reorder your capture sequence** so screens that push onto a stack come AFTER screens that need a clean stack. Example: capture Shelf first, then push into Coffee Detail — don't do it the other way around.

### 6. Widget views normally live in the extension target only

If the user's widget views are only in the widget extension target, you can't reference them from `MarketingCapture.swift` in the main app target. You need to either:

- **(a)** Add the widget view files (and their entry types and any shared helpers) to the main app target's membership. If the project uses synchronized folder groups, this means editing `PBXFileSystemSynchronizedBuildFileExceptionSet.membershipExceptions`. **CRITICAL GOTCHA: `membershipExceptions` is an INCLUSION list, not an exclusion list.** Files listed there ARE members of the target, not excluded from it. Read this twice before editing.
- **(b)** Skip widget rendering from the capture harness and let the user do them manually.

You'll also need to exclude `<App>WidgetBundle.swift` from the main app target (it has `@main` and conflicts with the app's `@main`).

### 7. `ImageRenderer` + `ProgressView(value:total:)` = prohibited symbol

Without an explicit style, `ProgressView` determinate renders as a red circle-with-slash when composited through ImageRenderer. Fix: `.progressViewStyle(.linear)` on the ProgressView. It's a no-op in normal rendering and fixes the render glitch.

### 8. `.containerBackground(for: .widget)` is a no-op outside widget context

When you render a widget view via ImageRenderer in the app, its `.containerBackground` does nothing — the widget's background is transparent, and pixels outside the content are bare. You must wrap the widget render with an explicit background color + rounded rect clip:

```swift
content()
    .padding(16)  // widget container normally provides this
    .frame(width: size.width, height: size.height)
    .background(theme.background)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
```

Home-screen widget corner radius on iPhone: ~22pt. Lock-screen accessory radius: ~8pt.

### 9. iPhone 8 Plus is gone on iOS 26

If the user asks for a "6.5\" iPhone" (legacy App Store size), note that iOS 26+ simulators don't include iPhone 8 Plus / iPhone 11 Pro Max. Options: (a) install an older iOS runtime via Xcode > Settings > Platforms, or (b) fall back to a modern 6.1\" like iPhone 17 for iOS 26 design features.

### 10. Locale launch arguments

Pass `-AppleLanguages (xx) -AppleLocale xx` at every `simctl launch`. The parens around the language code are mandatory (it's a plist array literal). Use `Locale.current.language.languageCode?.identifier` for folder naming — it's more robust than `Locale.current.identifier` which may include region suffixes like `en_US`.

### 11. SwiftUI animations in ImageRenderer

`ImageRenderer` captures a single frame — it doesn't wait for animations. If your component has an `.onAppear` animation (chart drawing, number counting up), the render may capture the initial state. Either disable the animation in capture mode or add an explicit delay before rendering:

```swift
try? await Task.sleep(for: .milliseconds(500))  // let onAppear animations finish
let renderer = ImageRenderer(content: view)
```

## Output Layout

```
marketing/
    <locale>/           e.g. en, de, es, fr, ja
        01-home.png
        02-<screen>.png
        ...
        NN-<screen>.png
        elements/
            card-<name>.png
            widget-<family>-<size>.png
            chart-<name>.png
```

Put `marketing/` in `.gitignore`. These are outputs, not source.

## Verification Checklist

Before declaring the capture pipeline done, verify:

- [ ] All locales produced N files (where N = screens + elements)
- [ ] File sizes differ between locales (confirms translations actually render — if `en/settings.png` and `de/settings.png` are byte-identical, locale switching didn't take effect)
- [ ] Read 2-3 screens visually for the primary locale and confirm they show the expected content
- [ ] Read the same screens for at least one other locale and confirm localized strings are present
- [ ] Read at least one widget render and one card render to verify backgrounds and corners look right
- [ ] No screenshot shows a screen from a *different* step (the most common bug — an undismissed sheet from the previous step)

## Templates

- `templates/MarketingCapture.swift.template` — skeleton of the capture file with step-based coordinator. Reference the body of this skill for the patterns to apply.
- `templates/capture-marketing.sh.template` — skeleton of the shell script. Replace the bundle ID, scheme name, and simulator name for each project.
