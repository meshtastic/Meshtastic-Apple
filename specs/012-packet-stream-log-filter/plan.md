# Implementation Plan: Packet Stream Log Filter

**Branch**: `012-packet-stream-log-filter` | **Date**: 2026-06-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/012-packet-stream-log-filter/spec.md`

## Summary

Add a **Packet Stream** mode to the in-app debug log viewer ([AppLog.swift](../../Meshtastic/Views/Settings/AppLog.swift)) that live-tails only over-the-air mesh packet traffic. The mode is the top control in the log filter; while active it overrides the Category/Level selections (Mesh category, all levels), continuously appends new packets pinned to the live edge, paces reveal to ≈6 entries/sec on busy meshes, retains 1,000 entries, and pauses on scroll-back / when off-screen. The filter sheet's Categories and Log Levels sections become collapsible accordions.

The packet signal is the existing **Mesh** logging category, made authoritative by an **audit**: non-packet lines currently emitted under `Logger.mesh` (config-received, admin/setup, persistence) move to `Logger.admin`/`Logger.data`, outbound packet sends currently under `Logger.transport` move to `Logger.mesh`, and the serial firehose stays under `Logger.radio`. Location/PII redaction (`privacy: .private`) is preserved everywhere it exists today.

Technical approach: there is no push/subscription API for the unified log store, so live tailing is implemented by polling `OSLogStore` and advancing the read position incrementally from the last-seen entry date (instead of re-scanning from boot as `Logger.fetch` does today), filtering to the Mesh category, buffering, and revealing at a paced cadence.

## Technical Context

**Language/Version**: Swift (latest stable), Swift Concurrency (`async`/`await`, `@MainActor`, `Task`)
**Primary Dependencies**: SwiftUI, OSLog (`OSLogStore`, `OSLogEntryLog`), existing `Logger` extension
**Storage**: N/A for the stream itself (reads the unified OSLog store, current-process scope); no SwiftData changes
**Testing**: Swift Testing (`@Suite`/`@Test`/`#expect`); SwiftUI snapshot tests for the restructured filter sheet
**Target Platform**: iOS / iPadOS / macOS (Catalyst), last two major OS versions
**Project Type**: Mobile app (single Xcode project, feature-folder structure)
**Performance Goals**: New packets visible ≤5s (SC-001); paced reveal ≈6 entries/sec under load (SC-008); smooth scroll under sustained traffic (SC-005)
**Constraints**: Bounded memory via 1,000-entry retention (FR-011); streaming pauses off-screen/backgrounded (FR-014); PII redaction preserved for export (FR-024); no UIKit; SFSymbols only
**Scale/Scope**: One new view-model/streamer type, edits to 2 log-viewer views, a logging audit across the inbound packet dispatch + outbound send paths; no schema/protobuf changes

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ Pass | All UI in SwiftUI under `Views/Settings/Logs/`; reusable bits stay in that feature folder. No navigation/Router change (the log screen is reached through existing settings navigation). |
| II. SwiftData Persistence | ✅ N/A | Feature reads `OSLogStore`, not SwiftData. No models, no schema migration. |
| III. Protocol-Oriented Transport | ✅ Pass | No transport changes. The audit only relocates `Logger` calls inside `AccessoryManager`/`MeshPackets`; it does not alter connection logic or bypass the Accessory layer. |
| IV. Structured Logging | ✅ Reinforces | The audit strengthens this principle — correct category usage (`.mesh` = packets, `.radio` = serial, `.admin` = config/admin, `.data` = persistence). No new category is introduced (decision in research.md); no `print()`. |
| V. Protobuf Contract Fidelity | ✅ N/A | No proto changes. |
| VI. Lint-Clean Commits | ✅ Pass | Pre-commit SwiftLint hook applies as usual. |
| VII. Platform Parity | ✅ Pass | Both phone and macCatalyst log-table layouts already exist and will both gain the streaming mode; conditional compilation kept. SFSymbols for the Packet Stream control. |
| VIII. Design Standards | ⚠️ Review | Filter accordion + Packet Stream toggle must follow the [Meshtastic Client Design Standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md). Fetch and review before finalizing the filter UI. |

**Gate result**: PASS (no violations; one design-standards review item tracked, no complexity justification needed).

## Project Structure

### Documentation (this feature)

```text
specs/012-packet-stream-log-filter/
├── plan.md              # This file
├── research.md          # Phase 0 output — streaming/pacing/audit decisions
├── data-model.md        # Phase 1 output — stream entities & state
├── quickstart.md        # Phase 1 output — manual verification
├── contracts/
│   └── log-viewer-ui-contract.md   # Phase 1 output — view/state & logging-category contract
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
Meshtastic/
├── Extensions/
│   └── Logger.swift                     # add incremental fetch (since-date) for live tail; categories unchanged
├── Views/Settings/
│   ├── AppLog.swift                     # add Packet Stream mode: live tail, pacing, auto-scroll/pause, empty state
│   └── Logs/
│       ├── AppLogFilter.swift           # Packet Stream toggle on top; Categories & Log Levels → accordions
│       ├── PacketStreamModel.swift      # NEW — @MainActor observable streamer: poll, buffer, pace, cap
│       └── LogDetail.swift              # unchanged (reused for entry detail)
└── Accessory/Accessory Manager/
    ├── AccessoryManager.swift           # AUDIT: processFromRadio dispatch (.mesh hygiene), send() outbound → .mesh, keep serial under .radio
    └── AccessoryManager+ToRadio.swift   # AUDIT: outbound packet sends → .mesh (preserve privacy markers)
Meshtastic/Helpers/
└── MeshPackets.swift                    # AUDIT: move config/admin/persistence lines off .mesh → .admin/.data

MeshtasticTests/
├── PacketStreamModelTests.swift         # NEW — pacing, cap/eviction, since-date filtering, ordering
└── SwiftUIViewSnapshotTests.swift       # add AppLogFilter accordion snapshot(s)
```

**Structure Decision**: Single Xcode project, existing feature-folder layout. The new logic is isolated in a `PacketStreamModel` under `Views/Settings/Logs/` so `AppLog.swift` stays a view. The logging audit is a cross-cutting edit to the Accessory + MeshPackets layers, kept behavior-preserving except for category reassignment.

## Complexity Tracking

> No constitution violations — section intentionally empty.
