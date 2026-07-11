# Implementation Plan: Site Planner Outbound Coverage Estimate

**Branch**: `015-site-planner-outbound` | **Date**: 2026-07-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/015-site-planner-outbound/spec.md`

## Summary

Let a user run a Meshtastic Site Planner RF-coverage estimate from inside the app — from a node's detail screen or from an arbitrary map location — and get the result back as a styled map overlay, with no browser and no share sheet. Technically: drive the planner (a client-side WASM SPLAT!/ITM simulator with no server API) inside a hidden `WKWebView` loaded at a flat query URL (`?lat=&lon=&...&run=1`); inject a `WKUserScript` shim so the planner's unconditional `window.__meshtasticNative.onCoverage(jsonString)` call reaches a `WKScriptMessageHandler`; hand the resulting GeoJSON string to a small new `MapDataManager.importFromData` entry point that reuses the existing (already-correct) file-import validation, styling, and persistence pipeline unchanged. Mirrors the shipped Android reference implementation (Meshtastic-Android#6136) for parameter scope, grouping, and entry points.

## Technical Context

**Language/Version**: Swift (latest stable), Swift Concurrency (`async`/`await`, `@MainActor`)
**Primary Dependencies**: SwiftUI, WebKit (`WKWebView`, `WKUserScript`, `WKScriptMessageHandler`) — new to this feature, no existing WKWebView usage in the codebase to follow as precedent (confirm during implementation)
**Storage**: SwiftData for existing config entities read at prefill time (no writes); the estimate result reuses the existing file-based `MapDataManager` storage (`MapData/user_uploaded/` + `upload_history.json`) unchanged — no new persisted entity
**Testing**: Swift Testing (`@Suite`/`@Test`/`#expect`/`#require`) in `MeshtasticTests/`; snapshot tests for new SwiftUI views per the project's `renderImage` helper
**Target Platform**: iOS 18+/iPadOS 18+ (last two major OS versions per Constitution VII) and macOS via Mac Catalyst
**Project Type**: Mobile app (single Xcode workspace, one app target + widgets/watch, not relevant here)
**Performance Goals**: SC-002 — ≥90% of default-value estimate submissions complete and render on a typical connection; no hard latency target since the simulation itself is a variable-cost remote computation outside this app's control
**Constraints**: No server-side API for the coverage computation exists (research.md §1) — the entire feature is bounded by what a real browser engine embedded in the app can do; only one estimate may run at a time app-wide (FR-007)
**Scale/Scope**: One new coordinator type, one new `MapDataManager` method, ~3 new SwiftUI surfaces (node-detail action, map-toolbar control, estimate form with 5 parameter sections), two small pure-logic helpers (region→power, preset→sensitivity)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design, and again (T029) after implementation.*

| Principle | Check | Status |
|---|---|---|
| I. SwiftUI-Native | Estimate form, map control, node-detail action are all SwiftUI; navigation continues through `Router`/existing sheet patterns (no new ad-hoc navigation state) | ✅ Pass |
| II. SwiftData Persistence | No new `@Model` entity — result reuses existing `MapDataManager` file-based storage; config *reads* use existing `@Query`/`LoRaConfigEntity` | ✅ Pass — see note below |
| III. Protocol-Oriented Transport | Not applicable — no device transport involved; reads existing SwiftData config only | ✅ N/A |
| IV. Structured Logging | `CoverageEstimateBridge`/`CoverageEstimateCoordinator`/`MapDataManager.importFromData` all use `Logger.services`, no `print()` | ✅ Pass |
| V. Protobuf Contract Fidelity | No protobuf changes — reads existing generated `LoRaConfigEntity`/`ModemPresets` fields only | ✅ Pass |
| VI. Lint-Clean Commits | **Verified, not assumed**: full-suite SwiftLint run (T028) reports 0 violations attributed to any of this feature's files | ✅ Pass — verified |
| VII. Platform Parity | Must work on iPhone, iPad, and Mac Catalyst equally. **iOS Simulator: fully verified** — `CoverageEstimateBridgeLiveSpikeTests` passed twice, independently, against the live site.meshtastic.org (6.3s and 20.7s real round trips). **Mac Catalyst: still genuinely open** (research.md §5) — blocked by environment issues on this dev machine (test target's deployment target vs. installed OS; an ad-hoc `open`-launched spike never presented a window), not by a confirmed WebKit failure. The bridge's design already commits to the safer attached-but-invisible approach as a hedge. | ⚠️ **Open** — re-run `CoverageEstimateBridgeLiveSpikeTests` via Xcode's Test navigator on a Catalyst destination before calling this fully verified |
| VIII. Design Standards Compliance | Live v1.4 doc fetched successfully (the "failure" during planning was a symlink-resolution red herring, not a real block — research.md §6). Findings applied and **visually verified** via snapshot, not just claimed: locale-aware `Measurement` conversion for height/range fields (2m → "6.6 ft", 30km → "18.6 mi"), plain-language subtext for RF jargon, a real placeholder-text bug caught and fixed by the visual check itself (an empty optional field showed its own label as a redundant placeholder) | ✅ Pass — verified, not deferred |

**Note on II**: `MapDataManager` storing overlays as flat files rather than SwiftData predates this feature (it already exists on `main`) and is out of scope to "fix" here — this plan extends it consistently rather than introducing a second, inconsistent storage mechanism. Not a new violation.

**T029 summary**: 6 of 8 principles fully pass with direct verification (not just process-compliance claims). One (VII) has a genuine, honestly-tracked open item — Mac Catalyst runtime behavior — that is an environment-access limitation on this specific machine, not a known defect. No principle is violated.

No entries required in Complexity Tracking — no gate is being violated, two are flagged as work carried into `tasks.md` rather than resolved here, which is what Phase 0/1 planning is for.

## Project Structure

### Documentation (this feature)

```text
specs/015-site-planner-outbound/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/            # Phase 1 output
│   ├── query-contract.md
│   └── native-bridge-contract.md
└── tasks.md              # Phase 2 output (/speckit-tasks — not created by this command)
```

### Source Code (repository root)

```text
Meshtastic/
├── Helpers/
│   ├── MapDataManager.swift          # MODIFY: add importFromData(_:suggestedName:)
│   ├── SitePlanner/                   # NEW folder
│   │   ├── CoverageEstimateBridge.swift        # WKWebView + WKUserScript + WKScriptMessageHandler coordinator
│   │   ├── CoverageEstimateCoordinator.swift   # Owns CoverageEstimateState; enforces single-in-flight rule
│   │   ├── CoverageEstimateParameters.swift    # The transient value type from data-model.md + validation
│   │   ├── CoverageQueryURLBuilder.swift       # Builds the flat query URL per contracts/query-contract.md
│   │   └── LoRaRFHelpers.swift                 # region→max power (watts), modemPreset→sensitivity (dBm)
│   └── LoRaChannelCalculator.swift    # REUSE UNCHANGED: radioFrequencyMHz(slot:) for tx_freq prefill
├── Views/
│   ├── Nodes/
│   │   ├── Helpers/
│   │   │   ├── NodeDetail.swift        # MODIFY: add "Estimate Coverage" action (position-gated)
│   │   │   └── Map/                    # map-toolbar control lives among the existing map helper views here
│   │   └── MeshMapMK.swift             # MODIFY: add map-toolbar coverage-estimate control
│   └── Helpers/
│       └── CoverageEstimateForm.swift  # NEW: the 5-section form (Site/Transmitter, Receiver, Simulation, Environment[advanced], Display)
└── Model/
    └── ConfigModels.swift              # READ ONLY: LoRaConfigEntity fields for prefill, no changes

MeshtasticTests/
├── CoverageEstimateParametersTests.swift   # NEW: validation rules from data-model.md
├── LoRaRFHelpersTests.swift                 # NEW: region→power, preset→sensitivity, against known reference values
├── MapDataManagerImportFromDataTests.swift  # NEW: importFromData against a canned FeatureCollection string
└── SwiftUIViewSnapshotTests.swift           # MODIFY: snapshot coverage for the new form + node-detail action
```

**Structure Decision**: Single-project mobile-app structure (matches the existing repo — no separate backend/frontend split, no new target). New logic lands in a dedicated `Meshtastic/Helpers/SitePlanner/` subfolder rather than scattering across existing files, since it's a cohesive, independently-testable unit (bridge, coordinator, parameters, URL builder, RF math) that only touches the rest of the app at two narrow seams: reading `LoRaConfigEntity` for prefill, and calling `MapDataManager.importFromData` on success. All new `.swift` files require explicit `project.pbxproj` entries (the `Meshtastic/` group is not a synchronized group) — silent no-compile is the known failure mode if this is skipped.

## Complexity Tracking

*No entries — no Constitution gate is violated. See Constitution Check notes above for the two items explicitly deferred to `tasks.md` rather than resolved in planning.*
