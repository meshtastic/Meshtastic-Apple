# Implementation Plan: Mesh Beacons

**Branch**: `014-mesh-beacons` | **Date**: 2026-07-04 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/014-mesh-beacons/spec.md`

## Summary

Mesh Beacons lets a Meshtastic node advertise its mesh (a `MESH_BEACON_APP` / port 37 `MeshBeacon`: message + optional offered channel/region/preset) and lets other nodes discover, join, and — proposed — broadcast them. The **receive/discovery** half (FR-001–FR-008: ingest during a scan, show in the summary, steer the scan, custom-channel tuning, Switch to this channel, Beacon Channels rows) is **already implemented** and plugs into the Local Mesh Discovery scan engine (spec 001). This plan covers the **unbuilt (PROPOSED)** work:

1. **Beacon join enhancement (FR-016–FR-017)** — an **Add channel** action that adds a beacon's channel to a free secondary slot with no reboot when no retune is needed, gated by a firmware-accurate frequency-slot derivation. (Primary near-term deliverable.)
2. **Beacon broadcast & config (FR-009–FR-014)** — a `ModuleConfig.MeshBeaconConfig` editor in Settings → Module Configuration to turn the user's own node into a beacon.
3. **Passive listen (FR-015)** — capture beacons heard outside a scan as session-less `DiscoveredBeacon`s in a reviewable list that also feeds the scan-setup rows.

Technical approach: pure SwiftUI + SwiftData + the existing `AccessoryManager` admin-message path and the upstream-generated `MeshBeacon`/`MeshBeaconConfig` protobufs — no new frameworks. The frequency-slot helper mirrors the firmware's `channel_num` name-hash so Add is only offered when it truly works.

## Technical Context

**Language/Version**: Swift (latest stable), Swift Concurrency (`actor`, `@MainActor`, `async`/`await`)
**Primary Dependencies**: SwiftUI, SwiftData, apple/swift-protobuf (MeshtasticProtobufs SPM package), `AccessoryManager`/`Transport` layer
**Storage**: SwiftData — existing `DiscoveredBeaconEntity` (relationships already optional, so a session-less passive beacon needs no schema change); `MeshBeaconConfig` is radio config (not persisted locally beyond the transient edit buffer)
**Testing**: Swift Testing (`@Suite`/`@Test`/`#expect`/`#require`); SwiftUI snapshot tests via the custom `renderImage` helper
**Target Platform**: iOS / iPadOS / macOS (Catalyst) — last two major OS versions (Constitution VII)
**Project Type**: Mobile/desktop app (single SwiftUI target + MeshtasticProtobufs SPM package + MeshtasticTests)
**Performance Goals**: 60 fps UI; config read/write is a single admin round-trip; frequency-slot derivation is O(1) and must not block the main actor
**Constraints**: Beacons are firmware-2.8-only; must degrade gracefully on older/no radio; offline-capable where it sends nothing to the radio; no reboot for Add; no silent config mutation (offers are advisory)
**Scale/Scope**: ~1 new config screen, 1 new action + supporting helper, optionally 1 passive-beacon list; a handful of new Swift Testing suites

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | PASS | New config editor + Add action are SwiftUI under `Views/Settings/`; navigation via `Router`. No UIKit. |
| II. SwiftData Persistence | PASS | Reuses `DiscoveredBeaconEntity` (optional session relationship already supports session-less passive beacons — no migration). No new persisted entity anticipated. |
| III. Protocol-Oriented Transport | PASS | Config write and channel add go through `AccessoryManager` admin-message helpers (`saveChannel`/`setModuleConfig`); no direct CoreBluetooth/Network. |
| IV. Structured Logging | PASS | Use `Logger` `.mesh`/`.admin` categories; no `print()`. |
| V. Protobuf Contract Fidelity | PASS | `MeshBeacon` + `MeshBeaconConfig` consumed from generated `MeshtasticProtobufs`; no hand-edits; convenience accessors in `Extensions/Protobufs/`. |
| VI. Lint-Clean Commits | PASS | Pre-commit SwiftLint; keep view bodies small to avoid type-check/lint issues. |
| VII. Platform Parity | PASS | SF Symbols; `#if targetEnvironment(macCatalyst)` where needed; feature works across iOS/iPadOS/Mac. |
| VIII. Design Standards | GATE | MUST fetch the [Meshtastic Client Design Standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md) before building the config editor UI. Tracked as a Phase 1 prerequisite. |

No violations requiring Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/014-mesh-beacons/
├── plan.md              # This file
├── spec.md              # Feature spec
├── research.md          # Phase 0 output (decisions / clarifications resolved)
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output (build/test/validate)
├── contracts/           # Phase 1 output (admin-message + helper contracts)
└── tasks.md             # /speckit.tasks output (NOT created here)
```

### Source Code (repository root)

```text
Meshtastic/
├── Model/
│   └── DiscoveredBeaconEntity.swift        # exists; passive beacons reuse it (session optional)
├── Services/
│   └── DiscoveryScanEngine.swift           # exists; beacon receive/steer lives here
├── Accessory/Accessory Manager/
│   ├── AccessoryManager+ToRadio.swift      # saveChannel / setModuleConfig admin writes (add MeshBeaconConfig write; addChannel-to-free-slot for Add)
│   └── AccessoryManager+FromRadio.swift    # beacon ingest (passive-listen hook, FR-015)
├── Extensions/
│   ├── Protobufs/                          # MeshBeacon/MeshBeaconConfig convenience accessors
│   └── LoraConfigEnums.swift               # add frequency-slot derivation helper (FR-017)
└── Views/Settings/
    ├── Config/Module/MeshBeaconConfig.swift   # NEW: broadcast/config editor (FR-009–014)
    └── Discovery/DiscoverySummaryView.swift    # add "Add channel" action + gating (FR-016)

MeshtasticTests/
├── ModemPresetFrequencySlotTests.swift     # NEW: slot derivation vs firmware vectors (FR-017)
├── BeaconAddVsSwitchTests.swift            # NEW: Add-vs-Switch gating logic (FR-016)
└── MeshBeaconConfigEditorTests.swift       # NEW: config validation (100-byte msg, 3600s interval)
```

**Structure Decision**: Single SwiftUI app target. Beacon config is a new Module Config screen (mirrors existing `Views/Settings/Config/Module/*`); the join enhancement extends `DiscoverySummaryView`; the frequency-slot helper extends `LoraConfigEnums.swift`. New `.swift` files MUST be registered in `project.pbxproj` (the `Meshtastic/` group is not a synchronized group).

## Complexity Tracking

No constitution violations — table intentionally empty.
