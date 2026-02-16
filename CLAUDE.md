# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Meshtastic-Apple is a SwiftUI client for Meshtastic mesh networking radios, targeting iOS, iPadOS, and macOS. It communicates with Meshtastic radio hardware over BLE, TCP, and serial connections, using Protocol Buffers for message serialization.

## Build & Development

- **Requires**: Latest Xcode release
- **Open**: `Meshtastic.xcworkspace` (not the .xcodeproj)
- **Setup**: Run `./scripts/setup-hooks.sh` after cloning to install the SwiftLint pre-commit hook
- **Protobuf regeneration**: `./scripts/gen_protos.sh` (requires `protoc` via `brew install swift-protobuf`). This pulls the latest `protobufs` git submodule and regenerates Swift files into `MeshtasticProtobufs/Sources/`
- **Tests**: Run the `MeshtasticTests` scheme in Xcode (XCTest-based, currently covers Router/URL routing)
- **Linting**: SwiftLint runs automatically via pre-commit hook and in CI on PRs. Config in `.swiftlint.yml`

## Architecture

### App Structure

Entry point is `MeshtasticApp.swift`. The app uses a TabView with five tabs: Messages, Connect, Nodes, Mesh Map, and Settings.

**State management**:
- `AppState` (ObservableObject) — holds the `Router` and unread message counts
- `Router` — handles deep linking via `meshtastic:///` URL scheme and `meshtastic.org/e/` / `meshtastic.org/v/` web URLs
- `AccessoryManager` (ObservableObject, singleton) — central device communication manager, injected as `@EnvironmentObject`
- `PersistenceController` (singleton) — CoreData stack, context passed via `.environment(\.managedObjectContext)`

### Device Communication Layer (`Meshtastic/Accessory/`)

`AccessoryManager` is split across extensions by responsibility:
- `AccessoryManager.swift` — state machine, lifecycle
- `+Discovery` — BLE scanning and device discovery
- `+Connect` — connection establishment
- `+ToRadio` — sending protobuf messages to the radio
- `+FromRadio` — receiving and processing protobuf messages from the radio
- `+MQTT` — MQTT gateway support (uses CocoaMQTT)
- `+Position` — GPS/location handling

Transport protocols are in `Meshtastic/Accessory/Transport/`: `BLETransport`, `TCPTransport`, `SerialTransport`.

### Data Layer

- **CoreData** is the persistence layer (39 model versions with migrations)
- Merge policy: `NSMergeByPropertyObjectTrumpMergePolicy` (in-memory wins)
- Key entities correspond to mesh network objects (nodes, messages, channels, waypoints, telemetry)
- SwiftUI views observe CoreData via `@FetchRequest`

### Protobuf Layer (`MeshtasticProtobufs/`)

Local Swift Package containing generated protobuf types. Import as `import MeshtasticProtobufs`. Types are prefixed `Meshtastic_` (e.g., `Meshtastic_MeshPacket`, `Meshtastic_FromRadio`, `Meshtastic_ToRadio`). The `protobufs/` directory is a git submodule pointing to the shared Meshtastic protobuf definitions.

### Enums (`Meshtastic/Enums/`)

Swift-native enum wrappers around protobuf enum values, providing display strings and UI helpers for configuration options (LoRa, Bluetooth, telemetry, routing, etc.).

## Key Conventions

- **Logging**: Use `Logger` extensions (`Logger.mesh`, `Logger.services`, `Logger.data`, `Logger.radio`, `Logger.transport`, `Logger.mqtt`, `Logger.admin`, `Logger.statistics`) — never use `print()` (enforced by SwiftLint custom rule)
- **UI**: SwiftUI only, SF Symbols for icons
- **OS support**: Last two major OS versions
- **Dependencies**: Managed via Swift Package Manager — CocoaMQTT for MQTT, Datadog SDKs for crash reporting/analytics, swift-protobuf for protobuf support
- **Branching**: Trunk-based development; all PRs target `main`. Use rebase, not merge, to incorporate upstream changes
- **Commit messages**: Imperative mood (e.g., "Fix bug" not "Fixed bug")
- **Indentation**: Swift source files use **tabs**, not spaces. The Edit tool's string matching is sensitive to this — if edits fail, verify whitespace with `cat -vet` (tabs show as `^I`)

## Building from CLI

- Build command: `xcodebuild build -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' -quiet`
- To find a valid simulator ID, run `xcrun simctl list devices available` and pick one
- The `-quiet` flag suppresses the `BUILD SUCCEEDED` banner; check for `error:` lines instead to detect failures
- Pre-existing warnings (MQTT actor isolation, LocationsHandler deprecations) are expected and not caused by new changes

## Commit Style

Use Conventional Commit style for all commits and PR titles (e.g. `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, etc.).
