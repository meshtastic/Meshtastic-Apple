# Tasks: Site Planner Outbound Coverage Estimate

**Input**: Design documents from `/specs/015-site-planner-outbound/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Included — the project constitution says new features SHOULD include Swift Testing coverage, and plan.md/quickstart.md already commit to specific test file names.

**Organization**: Tasks are grouped by user story (US1/US2/US3, matching spec.md's P1/P2/P3) so each can be implemented and demoed independently. All new `.swift` files need an explicit `project.pbxproj` entry — the `Meshtastic/` group is not synchronized, and a missing entry compiles silently without the new file (noted per-task below).

## Phase 1: Setup

- [X] T001 Create the `Meshtastic/Helpers/SitePlanner/` directory that will hold every new type in this feature (per plan.md's Project Structure)
- [X] T002 Fetch the live [Meshtastic Client Design Standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md) and note guidance on forms with grouped/collapsible sections, toolbar controls, node-detail actions, in-progress states, palette pickers, and error presentation (Constitution VIII) — **resolved: `_latest.md` is a symlink to `_v1_4.md`, fetched successfully; findings recorded in research.md §6** (Measurement-based unit display, plain-language subtext for advanced fields, null-data suppression, 44×44pt touch targets + Catalyst tooltips on icon-only controls)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared parameters type, RF math, URL builder, native bridge, and coordinator that every user story submits through. No story-specific UI belongs here.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T003 [P] Create `CoverageEstimateParameters` (all fields/sections) and its validation rules (position required, `rx_sensitivity` range, `max_range` cap incl. `high_res`, enum constraints) per data-model.md in `Meshtastic/Helpers/SitePlanner/CoverageEstimateParameters.swift` (register in project.pbxproj)
- [X] T004 [P] Add `CoverageEstimateParametersTests` covering every validation rule in `MeshtasticTests/CoverageEstimateParametersTests.swift` (register in project.pbxproj)
- [X] T005 [P] Implement `LoRaRFHelpers`: region code → max legal transmit power in watts (sourced from the firmware's own region table, not invented) and modem preset (spread factor + bandwidth) → receiver sensitivity in dBm (standard LoRa sensitivity math), in `Meshtastic/Helpers/SitePlanner/LoRaRFHelpers.swift` (register in project.pbxproj)
- [X] T006 [P] Add `LoRaRFHelpersTests` validating against known reference values (e.g. SF7/BW125 ≈ ‑124 dBm) in `MeshtasticTests/LoRaRFHelpersTests.swift` (register in project.pbxproj)
- [ ] T007 [P] Implement `CoverageQueryURLBuilder` turning a `CoverageEstimateParameters` into the flat query URL per contracts/query-contract.md (always includes `run=1`; omits unset optional keys so they fall back to planner defaults) in `Meshtastic/Helpers/SitePlanner/CoverageQueryURLBuilder.swift` (register in project.pbxproj) — depends on T003
- [ ] T008 [P] Add `CoverageQueryURLBuilderTests` verifying every key name and the omission rule against contracts/query-contract.md in `MeshtasticTests/CoverageQueryURLBuilderTests.swift` (register in project.pbxproj)
- [X] T009 [P] Add `MapDataManager.importFromData(_ data: Data, suggestedName: String) async throws -> MapDataMetadata`, mirroring `importFromRemote`'s temp-file-then-`processUploadedFile` pattern exactly, in `Meshtastic/Helpers/MapDataManager.swift`
- [X] T010 [P] Add `MapDataManagerImportFromDataTests` against a canned `FeatureCollection` string in `MeshtasticTests/MapDataManagerImportFromDataTests.swift` (register in project.pbxproj)
- [ ] T011 Implement `CoverageEstimateBridge`: a hidden `WKWebView`, the `WKUserScript` shim that defines `window.__meshtasticNative.onCoverage` and forwards to a `WKScriptMessageHandler`, and the handler decoding `WKScriptMessage.body` into the raw GeoJSON string — exactly per contracts/native-bridge-contract.md — in `Meshtastic/Helpers/SitePlanner/CoverageEstimateBridge.swift` (register in project.pbxproj) — depends on T007
- [ ] T012 SPIKE (blocking): empirically verify whether an off-screen/zero-frame `WKWebView` reliably executes JS and delivers `WKScriptMessageHandler` callbacks under Mac Catalyst (research.md §5, Constitution VII). If not, adjust `CoverageEstimateBridge` to attach to an invisible-but-present view before Phase 3 UI work depends on it — depends on T011
- [ ] T013 Implement `CoverageEstimateCoordinator`: a singleton owning `CoverageEstimateState`, enforcing exactly one in-flight run app-wide (FR-007), cancellation (FR-008), a timeout policy for "the bridge never called back" (contracts/native-bridge-contract.md's Timeout Policy note), routing a successful result into `MapDataManager.importFromData`, and logging every lifecycle transition via `Logger` (never `print`, per Constitution IV) — in `Meshtastic/Helpers/SitePlanner/CoverageEstimateCoordinator.swift` (register in project.pbxproj) — depends on T009, T012

**Checkpoint**: Foundation ready — every user story from here is UI-only, wiring existing pieces together.

---

## Phase 3: User Story 1 - Estimate coverage from a node's detail screen (Priority: P1) 🎯 MVP

**Goal**: A user with a positioned, connected node can run an estimate without leaving the app and see the result on the map.

**Independent Test**: Open a node with a known position, start "Estimate Coverage", submit with defaults, confirm a new named overlay appears on the mesh map with no browser/share sheet involved (spec.md Acceptance Scenario 1).

- [ ] T014 [US1] Add an "Estimate Coverage" action to the node detail screen, shown only when the node has a known position (FR-001; edge case: no position → action hidden, not disabled-and-confusing), in `Meshtastic/Views/Nodes/Helpers/NodeDetail.swift`
- [ ] T015 [US1] Build `CoverageEstimateForm` with the Site/Transmitter, Receiver, Simulation, and Display sections (Environment/advanced sections deferred to US3), prefilled from the node's position and the connected radio's `LoRaConfigEntity` — frequency via the existing `LoRaChannelCalculator.radioFrequencyMHz(slot:)`, power/sensitivity via T005's `LoRaRFHelpers` — falling back to factory defaults when no radio is connected (FR-003), in `Meshtastic/Views/Helpers/CoverageEstimateForm.swift` (register in project.pbxproj) — depends on T003, T005, T007
- [ ] T016 [US1] Wire form submission through `CoverageEstimateCoordinator`: show a clear in-progress state while running, block starting a second concurrent estimate (FR-007), and expose a cancel action (FR-008) — depends on T013, T015
- [ ] T017 [US1] On success, confirm the resulting overlay renders on the mesh map with the same styling as a file-imported overlay (FR-006); on failure/timeout, surface a specific, actionable message per `CoverageEstimateError` rather than a silent hang (FR-009) — depends on T016
- [ ] T018 [P] [US1] Add snapshot tests for `CoverageEstimateForm`'s default/prefilled state and the new node-detail action in `MeshtasticTests/SwiftUIViewSnapshotTests.swift`
- [ ] T019 [US1] Check `NodeDetail`'s new action and `CoverageEstimateForm`'s layout, section grouping, and iconography against the live Design Standards doc fetched in T002 (Constitution VIII) before considering this story done

**Checkpoint**: User Story 1 fully functional and independently demoable — this is the MVP.

---

## Phase 4: User Story 2 - Estimate coverage from an arbitrary map location (Priority: P2)

**Goal**: A user can run an estimate anywhere on the map, not just at an existing node.

**Independent Test**: From the map, start the estimate control, confirm the prefilled location matches the current map view (not `(0,0)` or stale), submit, and confirm the overlay lands at the intended coordinates (spec.md Acceptance Scenario 1 for US2).

- [ ] T020 [US2] Add a coverage-estimate control to the mesh map's toolbar (in `Meshtastic/Views/Nodes/MeshMapMK.swift` or the appropriate helper under `Meshtastic/Views/Nodes/Helpers/Map/` — confirm exact insertion point against the current toolbar layout at implementation time), opening the same `CoverageEstimateForm` from T015 but prefilling position from the current map view center rather than a node (FR-002) — depends on T015
- [ ] T021 [US2] Confirm the no-radio-connected fallback (FR-003) also works reached via the map control, not just from a node — depends on T020
- [ ] T022 [P] [US2] Add a snapshot test for the map-toolbar control's default state in `MeshtasticTests/SwiftUIViewSnapshotTests.swift`

**Checkpoint**: User Stories 1 AND 2 both work independently.

---

## Phase 5: User Story 3 - Tune advanced parameters before running an estimate (Priority: P3)

**Goal**: A power user can adjust simulation/display/environment parameters and see the result reflect the change.

**Independent Test**: Open the form, expand the advanced sections, change the color palette and max range away from defaults, submit, and confirm the resulting overlay visibly reflects both changes (spec.md Acceptance Scenarios for US3).

- [ ] T023 [US3] Extend `CoverageEstimateParameters`/`CoverageEstimateForm` with the Environment section (`clutter_height`, `ground_dielectric`, `ground_conductivity`, `atmosphere_bending`, `radio_climate`, `polarization`) and the Simulation section's advanced fields (`situation_fraction`, `time_fraction`), behind a disclosure so basic use is unaffected, sourcing the enum option lists from the exact code lists confirmed in `meshtastic-site-planner`'s `permalink.ts` constants at implementation time (contracts/query-contract.md's explicit non-goal against hand-copying them into docs) — depends on T015
- [ ] T024 [US3] Add the `color_scale` palette picker (`plasma` default, `viridis`, `CMRmap`, `cool`, `turbo`, `jet`) and `min_dbm`/`max_dbm`/`overlay_transparency` display controls to the Display section; verify end-to-end that changing the palette actually changes the rendered overlay's colors, not just the request sent — depends on T015
- [ ] T025 [P] [US3] Add a snapshot test for the expanded advanced/Environment section in `MeshtasticTests/SwiftUIViewSnapshotTests.swift`

**Checkpoint**: All three user stories independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T026 [P] Run the full manual validation checklist from quickstart.md (happy path, no-radio fallback, cancellation, concurrency guard, advanced params, forced failure/timeout, Mac Catalyst repeat of the happy path)
- [ ] T027 [P] Add a one-line entry to `docs/user/whats-new.md` per the constitution's documentation workflow (no `RELEASENOTES.md`)
- [ ] T028 Run the full `MeshtasticTests` suite and SwiftLint to confirm no regressions before opening the PR
- [ ] T029 Re-check Constitution gates now that implementation is complete: VII (Catalyst parity — resolved by T012's spike outcome) and VIII (design standards — resolved by T019 having actually happened, not skipped)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Setup — **blocks all user stories**. T012 (the Catalyst spike) is itself blocking within this phase: T013 depends on it, and by extension every story does too.
- **User Stories (Phase 3-5)**: All depend on Foundational completion. US2 and US3 both depend specifically on T015 (the form built in US1) — they are additive to it, not independent rebuilds, so they are not parallelizable with US1 the way the template's generic "stories can run in parallel" note assumes. US2 and US3 *are* independent of **each other** and could proceed in parallel once T015 exists.
- **Polish (Phase 6)**: Depends on all three stories being complete.

### Within Each Phase

- Tests are written alongside (not strictly before) implementation here, since most of Phase 2's units are pure/deterministic and the test task is listed as a parallel sibling `[P]` of its implementation task rather than a strict predecessor — adjust to test-first if you prefer, nothing here depends on ordering between a `T0XX`/`T0XX+1` implementation/test pair.
- Within Phase 2: T003→T007 (params before URL builder), T007→T011 (URL builder before the bridge that uses it), T011→T012 (build the bridge before spiking its Catalyst behavior), T012→T013, T009→T013 (coordinator needs both the bridge and the import path).
- Within Phase 3: T014 and T015 can proceed in parallel (different files), then T016 (needs T015 built) → T017 (needs T016 wired) → T018/T019 last.

### Parallel Opportunities

- Phase 2: T003, T005, T009 have no dependencies on each other and can start immediately together; T004/T006/T008/T010 (their respective tests) can run alongside once each's implementation counterpart exists.
- Phase 3: T014 (node-detail action) and T015 (the form itself) touch different files and can proceed in parallel.
- Phase 4 and Phase 5 can proceed in parallel with each other once T015 exists (they touch different toolbar/section code, not each other).

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Launch together — no cross-dependencies:
Task: "Create CoverageEstimateParameters + validation in Meshtastic/Helpers/SitePlanner/CoverageEstimateParameters.swift"
Task: "Implement LoRaRFHelpers (region→power, preset→sensitivity) in Meshtastic/Helpers/SitePlanner/LoRaRFHelpers.swift"
Task: "Add MapDataManager.importFromData(_:suggestedName:) in Meshtastic/Helpers/MapDataManager.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Foundational (T003-T013) — **the Catalyst spike (T012) is the highest-uncertainty item in the whole feature; do it early, don't leave it for polish**
3. Complete Phase 3: User Story 1 (T014-T019)
4. **STOP and VALIDATE**: run quickstart.md's happy-path + no-radio manual checks independently
5. Demo: node with a position → one tap → overlay on the map, no browser

### Incremental Delivery

1. Setup + Foundational → foundation ready, nothing user-visible yet
2. + User Story 1 → MVP: the core "estimate from a node" flow, demoable
3. + User Story 2 → map-location entry point added
4. + User Story 3 → power-user parameter tuning added
5. Each story adds value without touching what the previous one already shipped

---

## Notes

- [P] tasks touch different files and have no unresolved dependency between them.
- Every new `.swift` file needs a `project.pbxproj` entry — called out per task, but easy to forget; verify with a clean build (not just "no red squiggles in Xcode") before considering any task done.
- T012 (Catalyst spike) is the one task in this plan that could change the shape of T011/T013 after the fact — treat its outcome as a real go/no-go, not a formality.
- Constitution VIII (design standards) is enforced twice on purpose: once as a research gate (T002) and once as a per-story check (T019) — a stale mental summary from T002 is not sufficient for T019 if enough time has passed; re-fetch if in doubt.
