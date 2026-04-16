# GitHub Copilot Instructions for Meshtastic-Apple

## Project Overview

Meshtastic-Apple is a SwiftUI client for iOS, iPadOS, and macOS (via Mac Catalyst) that communicates with Meshtastic LoRa mesh radio devices over BLE, TCP, and serial transports. The app handles mesh networking, messaging, node management, mapping, and radio configuration.

## Architecture

### App Entry Point
- `Meshtastic/MeshtasticApp.swift` — `@main` `App` struct; initialises `AppState`, `Router`, `AccessoryManager`, `PersistenceController`, and Datadog observability.
- `Meshtastic/MeshtasticAppDelegate.swift` — `UIApplicationDelegate` for SiriKit intent handling (CarPlay messaging via `INSendMessageIntent` etc.).

### State & Navigation
- `Router` (`Meshtastic/Router/Router.swift`) is a `@MainActor` `ObservableObject` that owns a `NavigationState` struct and drives tab/deep-link routing.
- `NavigationState` and the per-tab enums (`MessagesNavigationState`, `MapNavigationState`, `SettingsNavigationState`) live in `Meshtastic/Router/NavigationState.swift`.
- Deep links use the `meshtastic:///` URL scheme (see README for the full table). `Router.route(url:)` dispatches them.
- `AppState` wraps `Router` and is passed as an `@EnvironmentObject` throughout the view hierarchy.

### Connectivity
- `AccessoryManager` (`Meshtastic/Accessory/Accessory Manager/`) is the central BLE/TCP/serial manager. It is split across extension files:
  - `AccessoryManager+Discovery.swift` — device scanning & connection
  - `AccessoryManager+Connect.swift` — connection lifecycle
  - `AccessoryManager+ToRadio.swift` — packets sent to the radio (including `sendWaypoint`)
  - `AccessoryManager+FromRadio.swift` — packets received from the radio
  - `AccessoryManager+Position.swift` — GPS position sharing
  - `AccessoryManager+MQTT.swift` — MQTT proxy
  - `AccessoryManager+TAK.swift` — TAK/CoT integration
- Transport protocols are in `Meshtastic/Accessory/Transports/`.

### Persistence
- Core Data is the sole persistence layer. Use `PersistenceController.shared` for the container; prefer `viewContext` for reads and a background context for writes.
- The model lives in `Meshtastic/Meshtastic.xcdatamodeld` (55+ versioned migrations — always add a new model version for schema changes).
- Query helpers: `QueryCoreData.swift` (`getNodeInfo`, etc.); update helpers: `UpdateCoreData.swift`.

### Protobufs
- The `MeshtasticProtobufs` Swift Package (`MeshtasticProtobufs/Package.swift`) wraps the protobuf-generated Swift sources.
- Regenerate with `./scripts/gen_protos.sh` whenever `protobufs/` submodule changes, then build and commit.

## Code Style

### Language & Frameworks
- **Swift only.** No Objective-C.
- **SwiftUI** for all UI. Do not use UIKit directly unless unavoidable (e.g., `UIApplicationDelegateAdaptor`).
- **SF Symbols** for all icons — never embed image assets for icons.
- **Core Data** for all persistence — do not introduce SQLite, Realm, or other persistence libraries.
- **OSLog / `Logger`** for all logging — never use `print()`. The project's SwiftLint config enforces this with a custom `disable_print` rule. Use the typed loggers defined in `Meshtastic/Extensions/Logger.swift`:
  - `Logger.admin`, `Logger.data`, `Logger.mesh`, `Logger.mqtt`, `Logger.radio`, `Logger.services`, `Logger.statistics`, `Logger.transport`, `Logger.tak`

### Platform Support
- Target the **last two major OS versions** of iOS, iPadOS, and macOS (Mac Catalyst).
- Guard iOS-only APIs with `#if !targetEnvironment(macCatalyst)` or `#if canImport(UIKit)`.

### SwiftLint
- SwiftLint is enforced on every commit via `scripts/setup-hooks.sh`. Ensure no new errors or warnings are introduced.
- Key limits (see `.swiftlint.yml`): line length 400, file length warning 3500, type body length warning 400, function body length warning 200, cyclomatic complexity warning 60.
- Disabled rules: `operator_whitespace`, `multiple_closures_with_trailing_closure`, `todo`, `trailing_whitespace`.

### Formatting Conventions
- Indent with **tabs**.
- Opening braces on the same line as the declaration.
- `// MARK: -` comments to separate logical sections within a file.
- `// MARK: FileName` or file-level copyright comment at the top of files.
- Extensions grouped by functionality in separate files (e.g., `AccessoryManager+ToRadio.swift`).
- Prefer `guard` for early exit; avoid deeply nested `if` blocks.
- Use trailing closure syntax; omit argument labels where idiomatic.

### Naming
- Types: `UpperCamelCase`, max 60 chars (warning at 60, error at 70).
- Variables/functions: `lowerCamelCase`, min 1 char, max 60 chars.
- Enum raw values that map to URL path segments use `lowerCamelCase` (e.g., `SettingsNavigationState.appSettings`).
- File names match the primary type they define.

### Concurrency
- `Router` is `@MainActor`; all property reads and method calls must be `await`-ed in async contexts and tests.
- Prefer `async/await` over callback-based APIs for new code.
- Use `Task` for fire-and-forget async work; propagate cancellation via `Task.checkCancellation()`.

## Testing

- Test target: `MeshtasticTests/`.
- Use **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`) for new tests. XCTest is used in some legacy test files.
- Tests are run via Xcode — there is no Makefile or CLI test runner.
- Ensure all existing tests pass before submitting a PR.
- Write tests for new features and bug fixes.

## Git & PR Workflow

- Branch from and target **`main`** (trunk-based development).
- Use **rebase** instead of merge to incorporate upstream changes (`git config pull.rebase true`).
- Keep branches small and focused on a single task.
- Commit messages: imperative mood subject line (e.g., `Fix crash when BLE device disconnects`). Explain *what* and *why* in the body.
- PR description must answer: what changed, why it changed, how it was tested, and include screenshots/videos when UI is affected (see `.github/pull_request_template.md`).
- Self-review code before requesting review; comment complex areas.

## Deep Links

The app registers the `meshtastic:///` URL scheme. Use `Router.route(url:)` to handle incoming URLs. When adding a new deep link:
1. Add a case to the appropriate `*NavigationState` enum in `NavigationState.swift`.
2. Update `Router`'s routing helpers.
3. Document the URL in the README.

## Adding or Updating Protobufs

1. Update the `protobufs/` git submodule.
2. Run `./scripts/gen_protos.sh`.
3. Build, test, and commit the generated changes.

## Core Data Schema Changes

1. Create a new model version in `Meshtastic.xcdatamodeld`.
2. Set it as the current version.
3. Add a migration policy if required (lightweight migration is preferred when possible).

## CI

CI is handled by Xcode Cloud via `ci_scripts/ci_pre_xcodebuild.sh`. Do not modify CI scripts without understanding the Xcode Cloud build environment.
