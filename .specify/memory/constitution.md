<!--
Sync Impact Report
  Version change: 1.2.0 → 1.3.0
  Modified principles: none
  Updated sections: none
  Added sections:
    - Principle VIII (Meshtastic Design Standards Compliance)
  Removed sections: N/A
  Templates requiring updates:
    - .specify/templates/plan-template.md ✅ no changes needed
    - .specify/templates/spec-template.md ✅ no changes needed
    - .specify/templates/tasks-template.md ✅ no changes needed
  Follow-up TODOs: None
-->

# Meshtastic Apple Constitution

## Core Principles

### I. SwiftUI-Native

All user interface code MUST be built with SwiftUI. UIKit views are
not permitted. New views MUST follow the existing feature-folder
structure under `Meshtastic/Views/` (e.g., `Messages/`, `Nodes/`,
`Settings/`, `Connect/`). Reusable view components MUST be placed in
`Meshtastic/Views/Helpers/`. Navigation state MUST flow through the
centralized `Router` — views MUST NOT manage their own tab or
deep-link routing.

**Rationale**: A single UI framework eliminates cross-paradigm
complexity and keeps the codebase approachable for contributors
familiar with modern Apple development.

### II. SwiftData Persistence

All persistent application data MUST be stored using SwiftData. The
`PersistenceController.shared` singleton owns the `ModelContainer`
and exposes a `ModelContext` via its `context` property. Model types
are defined with the `@Model` macro in `Meshtastic/Model/`. Views
MUST use `@Query` for reads and `@Environment(\.modelContext)` or
`@Bindable` for writes. Background processing MUST use the
`MeshPackets` `@ModelActor` which provides its own `ModelContext`.
Entity query helpers reside in
`Meshtastic/Persistence/QueryCoreData.swift`. Entity extensions
providing computed properties MUST be placed in
`Meshtastic/Extensions/CoreData/`. Schema evolution is managed via
`VersionedSchema` and `SchemaMigrationPlan` in
`Meshtastic/Model/MeshtasticSchema.swift`.

**Rationale**: SwiftData replaces Core Data with a modern,
Swift-native persistence API that integrates directly with SwiftUI
via `@Query` and `@Bindable`, eliminating boilerplate and improving
type safety.

### III. Protocol-Oriented Transport

All device communication MUST go through the `Transport` and
`Connection` protocol abstractions defined in
`Meshtastic/Accessory/Protocols/`. New transport types MUST implement
these protocols and be registered in `AccessoryManager`. Direct
CoreBluetooth or network calls outside the Accessory layer are not
permitted. The `AccessoryManager` singleton MUST be the single entry
point for connection lifecycle management. Legacy `BLEManager`
references MUST be migrated to `AccessoryManager` when touched.

**Rationale**: The protocol-oriented transport layer enables BLE, TCP,
and Serial transports to be swapped transparently. Centralizing
connection state prevents race conditions and duplicated logic.

### IV. Structured Logging

All diagnostic output MUST use the OSLog `Logger` extension defined in
`Meshtastic/Extensions/Logger.swift` with the appropriate category
(`.admin`, `.data`, `.mesh`, `.mqtt`, `.radio`, `.services`,
`.transport`, `.tak`). `print()` statements are banned and enforced by
the `disable_print` SwiftLint custom rule. New subsystem categories
MUST be added to the Logger extension when introducing a distinct
functional area.

**Rationale**: Structured, categorized logging enables effective
filtering in Console.app and integrates with the Datadog observability
pipeline. Unstructured print output is invisible in production.

### V. Protobuf Contract Fidelity

All Meshtastic wire-protocol types MUST be generated from the
`protobufs/` git submodule using `scripts/gen_protos.sh`. Hand-editing
generated `.pb.swift` files in `MeshtasticProtobufs/Sources/` is
forbidden. Proto extensions and convenience accessors MUST be placed
in `Meshtastic/Extensions/Protobufs/`. When upstream proto definitions
change, the generation script MUST be re-run and the resulting changes
committed atomically.

**Rationale**: Generated protobuf code ensures type-safe
interoperability with Meshtastic firmware. Manual edits create drift
that breaks cross-platform compatibility.

### VI. Lint-Clean Commits

All committed Swift code MUST pass SwiftLint validation. The
pre-commit hook (`scripts/hooks/pre-commit`) MUST remain active and
auto-fix lint issues on staged files. The project uses two SwiftLint
configurations: `.swiftlint.yml` for IDE use and
`.swiftlint-precommit.yml` for the commit hook. Generated code in
`MeshtasticProtobufs/` is excluded from linting. New SwiftLint rules
MUST NOT be disabled without documented justification.

**Rationale**: Automated lint enforcement at commit time prevents
style drift and keeps PRs focused on logic rather than formatting.

### VII. Platform Parity

The app MUST support the last two major OS versions on iOS, iPadOS,
and macOS (via Catalyst). Platform-specific code MUST use conditional
compilation (`#if targetEnvironment(macCatalyst)`,
`#if canImport(ActivityKit)`). Features available on one platform
SHOULD have graceful degradation or equivalent functionality on
others. SFSymbols MUST be used for all iconography to ensure
cross-platform rendering consistency.

**Rationale**: Meshtastic users span Apple devices. Conditional
compilation keeps a single codebase while respecting platform
capabilities.

### VIII. Meshtastic Design Standards Compliance

All UI work MUST comply with the
[Meshtastic Client Design Standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md).
This is the canonical, authoritative source for all visual and
interaction design requirements. Agents and contributors MUST fetch
and review this document before making UI changes. Do not rely on
summaries — always consult the latest version at the URL above.

**Rationale**: A single canonical design standards document prevents
drift between inline summaries and the authoritative source, ensuring
cross-platform consistency as standards evolve.

## Technology Stack & Constraints

- **Language**: Swift (latest stable), using Swift Concurrency
  (`actor`, `@MainActor`, `async`/`await`)
- **UI**: SwiftUI with `ObservableObject` / `@Published` state
  management
- **Persistence**: SwiftData (`ModelContainer` / `ModelContext`)
  with `VersionedSchema` migration
- **Networking**: CoreBluetooth (BLE), Network.framework (TCP),
  IOKit (Serial/macCatalyst), CocoaMQTT (MQTT proxy)
- **Protobufs**: apple/swift-protobuf (>= 1.33.3) via local SPM
  package
- **Observability**: Datadog SDK (RUM, Crash Reporting, Logs,
  Tracing, Session Replay on TestFlight)
- **Testing**: Swift Testing framework (`@Suite`, `@Test`,
  `#expect`, `#require`); custom SwiftUI snapshot renderer in
  `SwiftUIViewSnapshotTests.swift`
- **Snapshot Testing**: Custom `renderImage` helper using
  `UIHostingController` + `drawHierarchy(in:afterScreenUpdates:)`
  with safe-area negation. Reference PNGs stored in
  `MeshtasticTests/__Snapshots__/`.
- **Linting**: SwiftLint with pre-commit hook auto-fix
- **CI/CD**: Xcode Cloud with pre-build secrets injection
- **IDE**: Latest release version of Xcode
- **License**: GPL v3
- **Design Standards**: [Meshtastic Client Design Standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md)
- **Deep Links**: `meshtastic:///` URL scheme for navigation,
  shortcuts, and widget integration

## Development Workflow

- **Branching**: Trunk-based development targeting `main`. Release
  branches follow `X.YY.ZZ-release` naming via
  `scripts/create-release-branch.sh`.
- **Commits**: Imperative mood subject line. Body explains what and
  why. Rebase onto `main` before PR — no merge commits in feature
  branches.
- **Pull Requests**: Target `main`. Small, incremental,
  self-contained changes. PR description MUST clearly describe the
  change. Code review by a project maintainer is required before
  merge.
- **Testing**: All existing tests MUST pass before PR submission.
  New features and bug fixes SHOULD include tests using the Swift
  Testing framework in `MeshtasticTests/`. Do NOT use XCTest for
  new tests — use `import Testing`, `@Suite`, `@Test`, `#expect`,
  and `#require` exclusively. The one remaining XCTest file
  (`ChannelEntityTests.swift`) is legacy and SHOULD be migrated.
- **Snapshot Testing**: SwiftUI helper views SHOULD have snapshot
  tests in `MeshtasticTests/SwiftUIViewSnapshotTests.swift`. The
  custom `renderImage` function renders views via
  `UIHostingController` + `drawHierarchy` with safe-area inset
  negation. Reference PNGs are stored in
  `MeshtasticTests/__Snapshots__/SwiftUIViewSnapshotTests/` and
  MUST NOT be committed during initial recording — delete and
  re-record on a clean run. Tests that use `ScrollView` or
  expand beyond intrinsic size MUST pass an explicit `height:`
  parameter to `renderImage`.
- **Git Hooks**: Contributors MUST run `scripts/setup-hooks.sh` to
  install the pre-commit lint hook.
- **Protobuf Updates**: Run `scripts/gen_protos.sh`, build, test,
  and commit the generated changes.
- **Documentation**: Update project documentation to reflect changes.
  Release notes go in `Meshtastic/RELEASENOTES.md`.

## Governance

This constitution is the authoritative reference for architectural
decisions and development standards in the Meshtastic Apple
repository. All pull requests and code reviews MUST verify compliance
with these principles.

- **Amendments** require a documented rationale, maintainer approval,
  and an updated constitution version. Changes MUST include a
  migration plan if they affect existing code.
- **Versioning** follows semantic versioning: MAJOR for
  backward-incompatible principle changes, MINOR for new principles
  or expanded guidance, PATCH for clarifications and typo fixes.
- **Compliance review**: Maintainers SHOULD periodically audit the
  codebase against these principles, particularly during major
  releases.
- **Complexity justification**: Deviations from these principles
  MUST be justified in the PR description and approved by a
  maintainer.

**Version**: 1.3.0 | **Ratified**: 2026-04-15 | **Last Amended**: 2026-05-03
