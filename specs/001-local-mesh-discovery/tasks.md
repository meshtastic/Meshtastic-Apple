# Tasks: Local Mesh Discovery

**Input**: Design documents from `/specs/001-local-mesh-discovery/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/deep-links.md, quickstart.md

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization — Logger category, navigation plumbing, SwiftData model registration

- [X] T001 Add `Logger.discovery` category to `Meshtastic/Extensions/Logger.swift`
- [X] T002 [P] Add `case localMeshDiscovery` to `SettingsNavigationState` in `Meshtastic/Router/NavigationState.swift`
- [X] T003 [P] Create directory `Meshtastic/Views/Settings/Discovery/`
- [X] T004 [P] Create directory `Meshtastic/Services/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: SwiftData models and NeighborInfo processing that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Create `DiscoverySessionEntity` @Model in `Meshtastic/Model/DiscoverySessionEntity.swift` with all attributes and relationships per data-model.md
- [X] T006 [P] Create `DiscoveryPresetResultEntity` @Model in `Meshtastic/Model/DiscoveryPresetResultEntity.swift` with all attributes and relationships per data-model.md
- [X] T007 [P] Create `DiscoveredNodeEntity` @Model in `Meshtastic/Model/DiscoveredNodeEntity.swift` with all attributes, relationships, and computed `iconName` property per data-model.md (FR-011: messageCount >= sensorPacketCount → `person.2.fill`, else `thermometer.medium`)
- [X] T008 Register all 3 new model types in `MeshtasticSchema.allModels` array in `Meshtastic/Model/MeshtasticSchema.swift`
- [X] T009 Implement NeighborInfo packet forwarding in `Meshtastic/Accessory/Accessory Manager/AccessoryManager+FromRadio.swift` — in the `.neighborinfoApp` case, forward deserialized `NeighborInfo` to `DiscoveryScanEngine` when a scan is active (R-001); keep existing log for non-scan state
- [X] T010 Add deep link handling for `meshtastic:///settings/localMeshDiscovery` in `Meshtastic/Router/Router.swift` — set selectedTab to settings and push `.localMeshDiscovery` navigation state
- [X] T011 Add `NavigationLink(value: .localMeshDiscovery)` with SF Symbol `antenna.radiowaves.left.and.right` to `developersSection` in `Meshtastic/Views/Settings/Settings.swift`
- [X] T012 Add `.navigationDestination(for: SettingsNavigationState)` case for `.localMeshDiscovery` in `Meshtastic/Views/Settings/Settings.swift` — push `DiscoveryScanView()`

**Checkpoint**: Models registered, navigation wired, NeighborInfo forwarding ready — user story implementation can begin

---

## Phase 3: User Story 1 — Configure and Run a Multi-Preset Scan (Priority: P1) 🎯 MVP

**Goal**: User selects presets, sets dwell time, taps Start Scan. App cycles through presets sending AdminMessage config changes, reconnects after reboot, dwells while collecting packets, advances to next preset, and allows stop with home preset restore.

**Independent Test**: Connect to a radio, select one preset, set 15-min dwell, start scan, verify radio changes preset and app collects node/telemetry data during dwell.

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T043 [P] [US1] Create state machine unit tests in `MeshtasticTests/DiscoveryScanEngineTests.swift` — test all transitions: Idle→Shifting→Reconnecting→Dwell→Shifting→Analysis→Complete, stop from each active state→Restoring→Idle, Reconnecting→Paused→Shifting resume, skip-config-change-when-already-on-preset edge case
- [X] T044 [P] [US1] Create SwiftData model tests in `MeshtasticTests/DiscoveryModelTests.swift` — test entity creation, relationship cascades (delete session cascades to preset results and nodes), computed `iconName` property, `completionStatus` state transitions, `totalUniqueNodes` deduplication by nodeNum, dwell duration validation (900–10800 in 900 increments)

### Implementation for User Story 1

- [X] T013 [US1] Create `DiscoveryScanEngine` as `@MainActor @Observable` class in `Meshtastic/Services/DiscoveryScanEngine.swift` with state machine enum (Idle, Shifting, Reconnecting, Dwell, Analysis, Complete, Paused, Restoring) and published properties: `currentState`, `activePreset`, `dwellTimeRemaining`, `selectedPresets`, `dwellDuration`, `session: DiscoverySessionEntity?`. Use `Logger.discovery` for all state transitions and errors (constitution IV).
- [X] T014 [US1] Implement `startScan()` in `DiscoveryScanEngine` — record home preset, create `DiscoverySessionEntity` (status: inProgress), transition to Shifting, call `accessoryManager.saveLoRaConfig()` for first preset (FR-004); skip config change if already on target preset (edge case)
- [X] T015 [US1] Implement reconnection and pause/resume handling in `DiscoveryScanEngine` — observe BLE disconnect/reconnect via AccessoryManager notifications; on reconnect + `wantConfigComplete`, transition Reconnecting → Dwell; on 60s timeout, transition Reconnecting → Paused; on connection restored while Paused, transition Paused → Shifting to resume scan (FR-005, edge case: disconnect mid-dwell)
- [X] T016 [US1] Implement dwell timer in `DiscoveryScanEngine` — countdown timer using `Task.sleep`; on expiry, if more presets remain transition Dwell → Shifting for next preset, if last preset transition Dwell → Analysis (FR-006)
- [X] T017 [US1] Implement packet ingestion in `DiscoveryScanEngine` — receive forwarded packets (Position, NodeInfo, NeighborInfo, DeviceMetrics, EnvironmentMetrics, TEXT_MESSAGE_APP, LocalStats) during Dwell state; create/update `DiscoveredNodeEntity` records via main `ModelContext` (engine is `@MainActor`); classify direct vs mesh neighbors (FR-006, FR-007); apply 2-packet rule for DeviceMetrics channel utilization and airtime rate (FR-008)
- [X] T018 [US1] Implement `stopScan()` in `DiscoveryScanEngine` — transition current state → Restoring; save partial results to session (completionStatus: "stopped"); call `saveLoRaConfig()` with home preset; on restore complete transition Restoring → Idle (FR-015)
- [X] T019 [US1] Implement session finalization in `DiscoveryScanEngine` — compute aggregate session metrics (totalUniqueNodes deduplicated by nodeNum, averageChannelUtilization, furthestNodeDistance, totalTextMessages, totalSensorPackets); update `DiscoverySessionEntity` and all `DiscoveryPresetResultEntity` records (FR-014)
- [X] T020 [US1] Handle app termination edge case in `DiscoveryScanEngine` — on app launch, query for any session with completionStatus "inProgress" and mark as "interrupted" (edge case: app terminated during scan)
- [X] T021 [US1] Create `DiscoveryScanView` in `Meshtastic/Views/Settings/Discovery/DiscoveryScanView.swift` — multi-select preset picker (FR-001), dwell time stepper (15–180 min in 15-min increments per FR-003), Start/Stop Scan button, progress indicator showing active preset and remaining dwell time; requires connected radio
- [X] T022 [US1] Wire `DiscoveryScanView` to `DiscoveryScanEngine` — inject engine as `@State` or `@Environment`; bind UI controls to engine properties; enable Start only when ≥1 preset selected and radio connected

**Checkpoint**: Core scan engine works end-to-end — user can configure, start, dwell, advance presets, stop, and restore home preset

---

## Phase 4: User Story 2 — Visualize Discovered Nodes on a Map (Priority: P2)

**Goal**: During or after a scan, show a MapKit map with discovered nodes color-coded by neighbor type (green=direct, blue=mesh), topology polylines to direct neighbors, social/sensor icons, and radar sweep animation during active dwell.

**Independent Test**: Run a single-preset scan for 15 minutes with known nodes. Verify each heard node appears at correct coordinates with correct color and topology lines to direct neighbors.

### Tests for User Story 2

- [X] T045 [P] [US2] Create snapshot tests in `MeshtasticTests/DiscoverySnapshotTests.swift` — snapshot `DiscoveryMapView` with mock direct (green) and mesh (blue) nodes, snapshot `RadarSweepView` in active and inactive states; use project's custom `renderImage` helper per snapshot testing conventions

### Implementation for User Story 2

- [X] T023 [US2] Create `DiscoveryMapView` in `Meshtastic/Views/Settings/Discovery/DiscoveryMapView.swift` — SwiftUI `Map(position:bounds:scope:)` with `@Namespace` scope; `@Query` or bind to engine's `DiscoveredNodeEntity` list; `UserAnnotation()` for user position (FR-009)
- [X] T024 [US2] Implement node annotations in `DiscoveryMapView` — `ForEach` over discovered nodes; green `Annotation` for neighborType "direct", blue for "mesh"; use computed `iconName` property (`person.2.fill` or `thermometer.medium`) per FR-011 (FR-009)
- [X] T025 [US2] Implement topology polylines in `DiscoveryMapView` — `MapPolyline` from user position to each direct neighbor node; no lines drawn to mesh neighbors (FR-009)
- [X] T026 [P] [US2] Create `RadarSweepView` in `Meshtastic/Views/Settings/Discovery/RadarSweepView.swift` — translucent rotating gradient overlay using `Canvas` + `TimelineView` for 60fps animation; accepts `isActive: Bool` binding (FR-010, SC-004)
- [X] T027 [US2] Integrate `RadarSweepView` as overlay on `DiscoveryMapView` — show when scan engine state is `.dwell`; hide otherwise (FR-010)
- [X] T028 [US2] Embed `DiscoveryMapView` in `DiscoveryScanView` — show map below scan controls during and after a scan; map updates live as nodes are discovered

**Checkpoint**: Map displays discovered nodes with correct colors, icons, topology lines, and radar animation during active dwell

---

## Phase 5: User Story 3 — Review Scan Summary and AI Recommendation (Priority: P3)

**Goal**: After scan completion, show per-preset summary cards with metrics and an on-device AI natural-language recommendation leveraging current scan + historical data.

**Independent Test**: Complete a two-preset scan with known traffic. Verify per-preset metrics display correctly and AI recommendation references the best preset.

### Tests for User Story 3

- [X] T046 [P] [US3] Add snapshot test for `DiscoverySummaryView` in `MeshtasticTests/DiscoverySnapshotTests.swift` — snapshot summary with mock two-preset session data showing per-preset cards and fallback table (non-iOS 26 path)

### Implementation for User Story 3

- [X] T029 [US3] Create `DiscoverySummaryView` in `Meshtastic/Views/Settings/Discovery/DiscoverySummaryView.swift` — accepts a `DiscoverySessionEntity`; renders per-preset cards showing unique node count, message count, sensor packet count, average channel utilization, packet success/failure rates, furthest node distance (FR-012)
- [X] T030 [US3] Implement RF Health section in `DiscoverySummaryView` — display packet success and failure rates from LocalStats data when available; show placeholder when no LocalStats collected (FR-012)
- [X] T031 [US3] Implement Foundation Model AI recommendation in `DiscoverySummaryView` — gated with `if #available(iOS 26, *)` using `FoundationModels` framework; define `@Generable` struct for recommendation output; build prompt from current scan metrics + historical session summaries (FR-013, R-003); fallback to structured metrics table on unsupported devices
- [X] T032 [US3] Navigate to `DiscoverySummaryView` from scan engine Analysis → Complete transition in `DiscoveryScanView` — automatically present summary when scan completes; also accessible via tap from session history

**Checkpoint**: Summary view shows correct per-preset metrics; AI recommendation generated on supported devices with fallback on others

---

## Phase 6: User Story 4 — Persist and Review Past Sessions (Priority: P4)

**Goal**: Session History list showing all past scans sorted by date with detail navigation, saved map and summary display, and swipe-to-delete.

**Independent Test**: Complete a scan, force-quit, relaunch, navigate to Session History, verify saved session appears with correct metadata.

### Tests for User Story 4

- [X] T047 [P] [US4] Add snapshot test for `DiscoveryHistoryView` in `MeshtasticTests/DiscoverySnapshotTests.swift` — snapshot history list with mock sessions in complete/stopped/interrupted states

### Implementation for User Story 4

- [X] T033 [US4] Create `DiscoveryHistoryView` in `Meshtastic/Views/Settings/Discovery/DiscoveryHistoryView.swift` — `@Query(sort: \DiscoverySessionEntity.timestamp, order: .reverse)` list; each row shows date, presets scanned, node count, completion status badge (FR-016). Verify query performance meets SC-006 target (< 2 seconds load time) with `FetchDescriptor` limits if needed.
- [X] T034 [US4] Implement swipe-to-delete in `DiscoveryHistoryView` — `.onDelete` modifier with confirmation; delete session and cascade to associated preset results and discovered nodes (FR-016, FR-017)
- [X] T035 [US4] Implement session detail navigation in `DiscoveryHistoryView` — tap a row to push a detail view reusing `DiscoveryMapView` + `DiscoverySummaryView` with the saved session's data (FR-016)
- [X] T036 [US4] Add Session History navigation from `DiscoveryScanView` — toolbar button or link to `DiscoveryHistoryView` when past sessions exist
- [X] T048 [US4] Add deep link handling for `meshtastic:///settings/localMeshDiscovery/history` sub-route in `Meshtastic/Router/Router.swift` — push `DiscoveryHistoryView` after `.localMeshDiscovery` (contracts/deep-links.md)

**Checkpoint**: Users can browse, view details, and delete past discovery sessions; data survives app restart

---

## Phase 7: User Story 5 — 2.4 GHz Preset Gating (Priority: P5)

**Goal**: LORA_24 preset only appears in the picker when the connected hardware has a "2.4GHz" tag in DeviceHardware.

**Independent Test**: Connect to a non-2.4 GHz radio — verify LORA_24 absent. Connect to 2.4 GHz radio — verify it appears.

### Implementation for User Story 5

- [X] T037 [US5] Implement 2.4 GHz hardware tag check in `DiscoveryScanView` — query connected node's `DeviceHardwareEntity.tags` for `tag == "2.4GHz"` via `NodeInfoEntity.deviceHardware`; conditionally include `ModemPresets.LORA_24` in preset picker list (FR-002, R-005)

**Checkpoint**: LORA_24 preset correctly gated by hardware capability

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, logging, and validation across all stories

- [X] T038 [P] Audit `Logger.discovery` usage across all scan engine and view code — verify all state transitions, errors, and packet counts are logged per constitution IV; add any missing log calls
- [X] T039 [P] Handle "scan continues in background" edge case — ensure `DiscoveryScanEngine` is not owned by a view lifecycle; scan persists when user navigates away from Discovery screen and UI resumes on return
- [X] T040 Handle "no nodes discovered on a preset" display — preset card shows "0 nodes found" in summary; AI recommendation factors empty presets (spec edge case)
- [X] T041 Handle "NeighborInfo references unknown node" — count in summary statistics but omit from map if no position data (spec edge case)
- [X] T042 Run `quickstart.md` validation — verify build, navigation, scan flow, and test commands work end-to-end

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion — **BLOCKS all user stories**
- **User Story 1 (Phase 3)**: Depends on Phase 2 — core scan engine, no other story dependencies
- **User Story 2 (Phase 4)**: Depends on Phase 2 + Phase 3 (needs scan engine + discovered nodes)
- **User Story 3 (Phase 5)**: Depends on Phase 2 + Phase 3 (needs completed session data)
- **User Story 4 (Phase 6)**: Depends on Phase 2 + Phase 3 (needs persisted sessions)
- **User Story 5 (Phase 7)**: Depends on Phase 2 only (just preset picker gating)
- **Polish (Phase 8)**: Depends on all desired stories being complete

### User Story Dependencies

- **US1 (P1)**: Foundation only — **MVP, start here**
- **US2 (P2)**: Requires US1 scan engine producing `DiscoveredNodeEntity` records
- **US3 (P3)**: Requires US1 scan engine producing completed sessions; can run in parallel with US2
- **US4 (P4)**: Requires US1 scan engine producing persisted sessions; can run in parallel with US2/US3
- **US5 (P5)**: Foundation only — **can run in parallel with US1**

### Within Each User Story

- Models/entities before services
- Services before views
- Core implementation before integration/wiring
- Story complete before moving to next priority

### Parallel Opportunities

**Phase 1 (Setup)**: T001, T002, T003, T004 — all parallel (different files)

**Phase 2 (Foundational)**: T005, T006, T007 — all parallel (different model files); T009, T010, T011 — all parallel (different source files); T008 depends on T005–T007; T012 depends on T011

**Phase 3 (US1)**: T043, T044 parallel (test files, write first); T013 first (engine skeleton), then T014–T020 sequentially (state machine logic builds on itself); T021–T022 can start after T013 (view can be built in parallel with engine internals)

**Phase 4 (US2)**: T045 first (snapshot test, write first); T023 (map skeleton), then T024–T025 sequentially; T026 parallel with T023 (different file); T027–T028 after T023+T026

**Phase 5 (US3)**: T046 first (snapshot test, write first); T029, then T030–T032 sequentially

**Phase 6 (US4)**: T047 first (snapshot test, write first); T033, then T034–T036 sequentially; T048 parallel with T033 (different file)

**Phase 7 (US5)**: T037 standalone — can run any time after Phase 2

**Phase 8 (Polish)**: T038, T039 parallel; T040, T041 parallel; T042 last

---

## Implementation Strategy

### MVP Scope

**User Story 1 (Phase 3)** is the MVP — a working scan engine with preset cycling, dwell timer, packet collection, and basic UI controls. This alone delivers the core diagnostic value.

### Incremental Delivery

1. **Phase 1 + 2**: Infrastructure (quick, ~30 min)
2. **Phase 3 (US1)**: Core scan engine + basic UI (largest phase, highest value)
3. **Phase 7 (US5)**: 2.4 GHz gating (small, can slot in early)
4. **Phase 4 (US2)**: Discovery map (high visual impact)
5. **Phase 5 (US3)**: AI summary (depends on iOS 26 availability)
6. **Phase 6 (US4)**: Session history (persistence polish)
7. **Phase 8**: Edge cases and cleanup
