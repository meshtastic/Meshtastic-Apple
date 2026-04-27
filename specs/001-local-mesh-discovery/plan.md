# Implementation Plan: Local Mesh Discovery

**Branch**: `001-local-mesh-discovery` | **Date**: 2026-04-26 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-local-mesh-discovery/spec.md`

## Summary

Local Mesh Discovery is a diagnostic tool that cycles through LoRa modem presets, dwelling on each to collect packets, then produces a per-preset comparison with an AI-generated recommendation. The implementation adds 3 new SwiftData models, a scan engine coordinating AdminMessage preset changes with BLE reconnect handling, a MapKit-based discovery map with topology visualization, an on-device Foundation Model summary, and a session history view — all accessed from Settings > Developers.

## Technical Context

**Language/Version**: Swift (latest stable), Swift Concurrency (`async`/`await`, `@MainActor`)
**Primary Dependencies**: SwiftUI, MapKit, CoreBluetooth (via AccessoryManager), MeshtasticProtobufs, FoundationModels (iOS 26+)
**Storage**: SwiftData (`ModelContainer` / `ModelContext`)
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`), custom snapshot renderer
**Target Platform**: iOS 17+, iPadOS 17+, macOS (Catalyst) — last two major OS versions
**Project Type**: Mobile app (SwiftUI, single Xcode target)
**Performance Goals**: 60 fps radar animation during dwell; session history loads < 2 seconds (SC-004, SC-006)
**Constraints**: Offline-capable (BLE only); on-device AI fallback to structured table on unsupported hardware
**Scale/Scope**: 3 new views, 3 new SwiftData models, 1 scan engine service, ~8 source files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|-----------|------------|-------|
| I. SwiftUI-Native | **PASS** | All new views use SwiftUI. Map uses `Map {}` with `Annotation`. Navigation via `Router` + `SettingsNavigationState.localMeshDiscovery`. |
| II. SwiftData Persistence | **PASS** | 3 new `@Model` types in `Meshtastic/Model/`. Views use `@Query`. Engine writes via main `ModelContext` (engine is `@MainActor`). |
| III. Protocol-Oriented Transport | **PASS** | Preset changes use existing `saveLoRaConfig` via `AccessoryManager`. No direct CoreBluetooth calls. |
| IV. Structured Logging | **PASS** | New `Logger.discovery` category for scan engine events. |
| V. Protobuf Contract Fidelity | **PASS** | Uses existing `AdminMessage`, `NeighborInfo`, `DeviceMetrics` protos. No hand-edits. |
| VI. Lint-Clean Commits | **PASS** | All new code passes SwiftLint. |
| VII. Platform Parity | **PASS** | FoundationModels gated with `#available(iOS 26, *)` — falls back to structured table. MapKit works on all targets. Developers section already `#if DEBUG`-gated. |

## Project Structure

### Documentation (this feature)

```text
specs/001-local-mesh-discovery/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (deep link contract)
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
Meshtastic/
├── Model/
│   ├── DiscoverySessionEntity.swift        # @Model — session aggregate
│   ├── DiscoveryPresetResultEntity.swift   # @Model — per-preset metrics
│   └── DiscoveredNodeEntity.swift          # @Model — per-node observation
├── Extensions/
│   └── Logger.swift                        # + Logger.discovery category
├── Accessory/
│   └── Accessory Manager/
│       └── AccessoryManager+FromRadio.swift # + NeighborInfo packet handling
├── Router/
│   └── NavigationState.swift               # + .localMeshDiscovery case
├── Views/
│   └── Settings/
│       ├── Settings.swift                  # + NavigationLink in developersSection
│       └── Discovery/
│           ├── DiscoveryScanView.swift     # Preset picker + scan controls + timer
│           ├── DiscoveryMapView.swift      # MapKit map + annotations + radar
│           ├── DiscoverySummaryView.swift  # Per-preset cards + AI recommendation
│           ├── DiscoveryHistoryView.swift  # Session list + detail navigation
│           └── RadarSweepView.swift        # Canvas + TimelineView radar overlay
└── Services/
    └── DiscoveryScanEngine.swift           # State machine, dwell timer, packet routing

MeshtasticTests/
├── DiscoveryScanEngineTests.swift          # State machine unit tests
├── DiscoveryModelTests.swift               # Entity tests
└── DiscoverySnapshotTests.swift            # Snapshot tests for new views
```

**Structure Decision**: Feature views grouped under `Views/Settings/Discovery/` since entry point is Settings > Developers. Scan engine is a standalone `@Observable` service in `Services/` — it coordinates `AccessoryManager` calls and SwiftData writes but doesn't own UI state.
