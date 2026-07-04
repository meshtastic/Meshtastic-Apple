---

description: "Task list for Mesh Beacons (unbuilt work)"
---

# Tasks: Mesh Beacons

**Input**: Design documents from `/specs/014-mesh-beacons/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/admin-and-helpers.md, quickstart.md

**Tests**: INCLUDED — the plan and quickstart call for specific Swift Testing suites, so test tasks are generated. Use Swift Testing (`@Suite`/`@Test`/`#expect`/`#require`), not XCTest.

**Scope note**: The beacon **receive/display/steer** side (FR-001–FR-008) is already implemented. These tasks cover only the **unbuilt (PROPOSED)** work: US1's Add-vs-Switch join enhancement (FR-016/FR-017) + passive listen (FR-015), and US2's broadcast/config editor (FR-009–FR-014).

**Reminder**: `Meshtastic/` is NOT a synchronized Xcode group — every new `.swift` file MUST be registered in `Meshtastic.xcodeproj/project.pbxproj` (4 entries) or it silently won't compile.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 / US2 (setup, foundational, and polish tasks have no story label)

---

## Phase 1: Setup (Shared Infrastructure)

- [ ] T001 Fetch and review the [Meshtastic Client Design Standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md) before any UI work (Constitution VIII).
- [ ] T002 Confirm a green baseline: `xcodebuild -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipMacroValidation build` on branch `014-mesh-beacons`.
- [ ] T003 [P] Add `MeshBeacon` / `ModuleConfig.MeshBeaconConfig` convenience accessors (flag get/set helpers, offered-field readers) in `Meshtastic/Extensions/Protobufs/MeshBeacon+Extensions.swift`; register the new file in `Meshtastic.xcodeproj/project.pbxproj`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared pieces both stories build on.

- [ ] T004 Verify `DiscoveredBeaconEntity.session`/`.presetResult` are optional so a session-less passive beacon needs no schema migration (data-model.md); if any non-optional assumption exists in queries, fix it. File: `Meshtastic/Model/DiscoveredBeaconEntity.swift`.
- [ ] T005 [P] Add the `.mesh`/`.admin` `Logger` call sites plan for the new flows (no new subsystem needed) — confirm categories exist in `Meshtastic/Extensions/Logger.swift`.

**Checkpoint**: Foundation ready — US1 and US2 can proceed in parallel.

---

## Phase 3: User Story 1 — Add-vs-Switch join + passive listen (Priority: P1) 🎯 MVP

**Goal**: Let a user join a beaconed mesh with **Add channel** (no reboot) when no retune is needed, falling back to **Switch** otherwise; and capture beacons heard outside a scan.

**Independent Test**: With two radios — (a) a beacon on your current preset/region/frequency shows **Add channel**, confirming adds a secondary channel with no reboot and you message both meshes; (b) a beacon on a different frequency/preset/region shows only **Switch** (reboot); (c) with listening on and no scan, a heard beacon appears in the Beacons list and pre-selects in the next scan setup.

### Tests for User Story 1 ⚠️ (write first, ensure they fail)

- [ ] T006 [P] [US1] `ModemPresetFrequencySlotTests` in `MeshtasticTests/ModemPresetFrequencySlotTests.swift` — assert `frequencySlot(name:preset:region:)` against known firmware vectors (default "LongFast" US slot), same-name→same-slot, different-name→different-slot (contract C5). Register in pbxproj.
- [ ] T007 [P] [US1] `BeaconAddVsSwitchTests` in `MeshtasticTests/BeaconAddVsSwitchTests.swift` — `beaconJoinOption` returns `.add` on matching slot, `.switchOnly` on any slot/preset/region mismatch, `.none` with no channel or no radio; and the Add write picks the lowest free secondary slot without touching primary (contracts C3, C6). Register in pbxproj.

### Implementation for User Story 1

- [ ] T008 [US1] Implement pure `frequencySlot(channelName:preset:region:) -> Int` mirroring the firmware `channel_num` name-hash in `Meshtastic/Enums/LoraConfigEnums.swift` (contract C5, FR-017).
- [ ] T009 [US1] Implement `BeaconJoinOption` + `beaconJoinOption(for:beacon:currentConfig:)` decision (`.add` / `.switchOnly` / `.none`) using T008, in `Meshtastic/Views/Settings/Discovery/DiscoverySummaryView.swift` (or a small helper file, registered) (contract C6, FR-016).
- [ ] T010 [US1] Add an **Add channel** action to the beacon card in `DiscoverySummaryView.swift`, shown only for `.add`; keep **Switch** for `.switchOnly` (FR-016).
- [ ] T011 [US1] Implement the secondary-slot write in `Meshtastic/Accessory/Accessory Manager/AccessoryManager+ToRadio.swift` — `saveChannel` into the lowest free secondary slot (role `.secondary`), no LoRa write, no reboot; on no free slot present a replace-a-secondary picker (never primary) (contract C3, D2).
- [ ] T012 [US1] Add primary-channel snapshot + rollback to `joinBeaconMesh` in `AccessoryManager+ToRadio.swift`: if the channel write succeeds but the LoRa/region/preset apply fails, restore the primary and surface the error (contract C4, D3).
- [ ] T013 [US1] Passive-listen ingest: in `Meshtastic/Accessory/Accessory Manager/AccessoryManager+FromRadio.swift` (`.meshBeaconApp` path), when `FLAG_LISTEN_ENABLED` and no active scan, persist a session-less `DiscoveredBeacon` (session/presetResult nil), ignoring self-beacons and duplicates (contract C7, FR-015).
- [ ] T014 [US1] A reviewable Beacons list surfacing session-less beacons (`@Query` where `session == nil`), reachable from the Discovery area, with delete; confirm these rows feed the existing scan-setup preset/channel rows (FR-015). New view registered in pbxproj.
- [ ] T015 [US1] Handle empty-PSK offered channels as the default/public key, labeled "open channel," in the Add/Switch paths (D5).
- [ ] T016 [US1] `Logger.mesh`/`.admin` logging for Add/Switch/passive-ingest; no `print()` (Constitution IV).

**Checkpoint**: US1 fully functional and independently testable — Add-vs-Switch + passive listen work without US2.

---

## Phase 4: User Story 2 — Broadcast a beacon from my own node (Priority: P2)

**Goal**: A `ModuleConfig.MeshBeaconConfig` editor so the user's node can advertise its mesh.

**Independent Test**: Enable broadcast on radio A (message, offered channel/region/preset, interval); radio B running discovery captures the beacon with all fields intact. A 101-byte message and a 3599 s interval are both blocked with inline errors.

### Tests for User Story 2 ⚠️ (write first, ensure they fail)

- [ ] T017 [P] [US2] `MeshBeaconConfigEditorTests` in `MeshtasticTests/MeshBeaconConfigEditorTests.swift` — message-length boundary (100/101 bytes) blocks save, interval boundary (3599/3600) blocks save, non-edited `flags` bits preserved, `BroadcastTarget.channel_index` validation (contract C2). Register in pbxproj.

### Implementation for User Story 2

- [ ] T018 [US2] Read path: surface the connected node's `ModuleConfig.meshBeacon` into an editor buffer (contract C1); confirm config sync in `AccessoryManager+FromRadio.swift` exposes it.
- [ ] T019 [US2] Create `Meshtastic/Views/Settings/Config/Module/MeshBeaconConfig.swift` — SwiftUI editor: `FLAG_LISTEN_ENABLED`/`FLAG_BROADCAST_ENABLED` toggles (preserve other bits), message field, offered channel/region/preset, interval, and the full multi-target list (`broadcast_targets` + `broadcast_send_as_node`) plus single-target scalars (FR-010–FR-014). Register in pbxproj.
- [ ] T020 [US2] Blocking client-side validation with inline errors: message ≤ 100 UTF-8 bytes (FR-011), interval ≥ 3600 s (FR-013); no silent truncation/clamp.
- [ ] T021 [US2] Write path: save via `AdminMessage.setModuleConfig(.meshBeacon(...))` through `AccessoryManager+ToRadio.swift` (contract C2); `FLAG_LEGACY_SPLIT` managed automatically (D4).
- [ ] T022 [US2] Add the editor to the Settings → Module Configuration list next to the other module configs, gated on 2.8 firmware; graceful unsupported state otherwise (FR-009, Constitution VII).

**Checkpoint**: US1 and US2 both work independently.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [ ] T023 [P] Snapshot tests for the beacon card **Add channel** state and the MeshBeaconConfig editor in `MeshtasticTests/SwiftUIViewSnapshotTests.swift` (delete/re-record references on a clean run).
- [ ] T024 [P] Docs: add `docs/user/whats-new.md` + `docs/user/discovery.md` (or a beacon page) entries; run `scripts/build-docs.sh --output Meshtastic/Resources/docs`; keep DeviceHardware.json/image_manifest.json churn out of the commit.
- [ ] T025 Keep spec ↔ research clarifications in sync — the four prior `[NEEDS CLARIFICATION]` items are now resolved in both spec and research (empty-PSK → D5, Switch-rollback → D3, `FLAG_LEGACY_SPLIT` → D4, no-free-slot → D2); verify no open `[NEEDS CLARIFICATION]` remains before `/speckit-implement`.
- [ ] T026 Lint-clean pass (SwiftLint) and confirm all new `.swift` files are registered in `project.pbxproj` (build fails-open otherwise).
- [ ] T027 Run quickstart.md validation (2-radio Add/Switch/no-free-slot/config-round-trip; offline via the `--meshtastic-seed-beacons` seed) and confirm SC-003, SC-006, SC-007 and no regression of the existing discovery suites (SC-005).

---

## Dependencies & Execution Order

- **Setup (Phase 1)** → **Foundational (Phase 2)** → **US1 (Phase 3)** and **US2 (Phase 4)** (independent; can run in parallel after Phase 2) → **Polish (Phase 5)**.
- Within US1: T006/T007 (tests) → T008 (`frequencySlot`) → T009 (decision) → T010/T011 (Add UI + write) → T012 (rollback) → T013/T014 (passive) → T015/T016.
- Within US2: T017 (tests) → T018 (read) → T019 (editor) → T020 (validation) → T021 (write) → T022 (list entry).

## Parallel Opportunities

- T003, T005 (Phase 1/2, different files).
- US1 tests T006 + T007 in parallel; US2 test T017 in parallel with US1 work (different files, different story).
- US1 and US2 whole phases in parallel once Foundational is done (touch mostly disjoint files; only `AccessoryManager+ToRadio.swift` is shared — sequence T011/T012 vs T021 if worked concurrently).

## Implementation Strategy

- **MVP = US1 (Add-vs-Switch + passive listen)** — the near-term deliverable the user asked for. Complete Phases 1–3, validate independently, ship.
- **US2 (config editor)** is the larger follow-on; deliver incrementally after US1.

## Notes

- Tests use Swift Testing only; write them to fail first.
- Offers are advisory — never auto-apply (FR-008); all radio writes go through `AccessoryManager` (Constitution III).
- Commit after each task or logical group; keep view bodies small to avoid type-check/lint issues.
