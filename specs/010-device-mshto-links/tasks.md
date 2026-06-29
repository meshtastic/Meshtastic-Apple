# Tasks: Device msh.to Links

**Input**: Design documents from `/specs/010-device-mshto-links/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, quickstart.md ✅

**Tests**: Included — spec references Swift Testing (`@Suite`, `@Test`, `#expect`).

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Phase 1: Setup

**Purpose**: Bundle the data source and prepare project structure

- [x] T001 Download and bundle `urls.json` from meshtastic/msh.to repository into `Meshtastic/Resources/urls.json`
- [x] T002 Add `urls.json` to the Xcode project target membership (Copy Bundle Resources)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: SwiftData model and schema migration that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 Create `DeviceLinkEntity` SwiftData model in `Meshtastic/Model/DeviceLinkEntity.swift` with fields: shortCode (unique), originalUrl, linkDescription, vendorDomain, vendorPriority; relationship `devices: [DeviceHardwareEntity]`
- [x] T004 Add `links: [DeviceLinkEntity]` inverse relationship on `DeviceHardwareEntity` in `Meshtastic/Model/DeviceHardwareEntity.swift`
- [x] T005 Register `DeviceLinkEntity` in the `ModelContainer` schema array in `Meshtastic/MeshtasticApp.swift` (no migration needed — shipping as v1 with this entity)

**Checkpoint**: Schema compiles and app launches without migration errors

---

## Phase 3: User Story 1 — View msh.to Links for Connected Device (Priority: P1) 🎯 MVP

**Goal**: Users see relevant msh.to links in the node info/hardware detail view for their connected device.

**Independent Test**: Connect to a device, open node info, verify links section appears with correct URLs sorted by vendor priority.

### Tests for User Story 1

- [x] T006 [P] [US1] Write unit tests for JSON decoding and import logic in `MeshtasticTests/DeviceLinkTests.swift`
- [x] T007 [P] [US1] Write unit tests for substring matching (shortCode contains hwModelSlug) in `MeshtasticTests/DeviceLinkTests.swift`
- [x] T008 [P] [US1] Write unit tests for vendor priority sorting (including locale-aware regional preference: US→Rokland priority 1, EU→Hexaspot priority 1, other→priority 2) in `MeshtasticTests/DeviceLinkTests.swift`

### Implementation for User Story 1

- [x] T009 [US1] Implement `importDeviceLinks()` method in `Meshtastic/API/MeshtasticAPI.swift` — decode bundled `urls.json`, insert-or-create `DeviceLinkEntity` records, extract vendorDomain from URL host, assign vendorPriority (0=manufacturer, 1=regional adjusted by `Locale.current.region`, 2=marketplace). Skip entries with invalid URLs and log warning.
- [x] T010 [US1] Implement substring matching in `importDeviceLinks()` — for each `DeviceHardwareEntity`, find links whose `shortCode` contains `hwModelSlug` (case-insensitive) and set the many-to-many relationship
- [x] T011 [US1] Call `importDeviceLinks()` at the end of `refreshDevicesAPIData()` in `Meshtastic/API/MeshtasticAPI.swift`
- [x] T012 [US1] Create `DeviceLinksSection.swift` in `Meshtastic/Views/Nodes/Helpers/` — SwiftUI view showing a "Links" section with tappable rows (link description + SF Symbol `safari` icon), sorted by vendorPriority, opening URL via `openURL` environment action
- [x] T013 [US1] Integrate `DeviceLinksSection` into the existing node info/hardware detail view (conditionally shown only when device has ≥1 link)
- [x] T014 [US1] Add `Logger.services` logging for import count, match count, and any skipped invalid URLs in `Meshtastic/API/MeshtasticAPI.swift`

**Checkpoint**: User Story 1 fully functional — device links visible in node info view

---

## Phase 4: User Story 2 — Links Stay Current via Background Refresh (Priority: P2)

**Goal**: Link data updates automatically when the bundled file changes across app updates.

**Independent Test**: Modify a link URL in bundled `urls.json`, rebuild, verify updated URL appears after refresh.

### Implementation for User Story 2

- [x] T015 [US2] Implement upsert logic in `importDeviceLinks()` — find existing `DeviceLinkEntity` by shortCode, update `originalUrl`/`linkDescription`/`vendorDomain`/`vendorPriority` if changed
- [x] T016 [US2] Handle removed links — delete `DeviceLinkEntity` records whose shortCode no longer exists in the bundled file (orphan cleanup)
- [x] T017 [P] [US2] Write unit test verifying upsert updates existing records and orphan cleanup removes stale links in `MeshtasticTests/DeviceLinkTests.swift`

**Checkpoint**: Links refresh correctly on app update with new bundled data

---

## Phase 5: User Story 3 — Browse All msh.to Links (Priority: P3)

**Goal**: Users can explore all msh.to links in a categorized directory view in Settings.

**Independent Test**: Open directory view, verify all links displayed grouped by vendor domain, tapping opens Safari.

### Implementation for User Story 3

- [x] T018 [US3] Create `DeviceLinkDirectory.swift` in `Meshtastic/Views/Settings/` — SwiftUI view with `@Query` fetching all `DeviceLinkEntity` records, grouped by `vendorDomain`, sorted by vendorPriority within groups
- [x] T019 [US3] Add navigation link to `DeviceLinkDirectory` from the Settings view (appropriate section)
- [x] T020 [P] [US3] Write unit test verifying non-device links (no matching hwModelSlug) are retained and queryable in `MeshtasticTests/DeviceLinkTests.swift`

**Checkpoint**: All user stories independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T021 [P] Update `docs/user/nodes.md` with documentation about hardware info panel (support tiers), and the "I want one" device purchase links section
- [x] T022 [P] Update `docs/user/settings.md` with documentation about the Device Links directory and Erase All App Data repopulating the device catalog
- [x] T023 Run `bash scripts/build-docs.sh --output Meshtastic/Resources/docs` to regenerate bundled HTML
- [ ] T024 Run quickstart.md validation — build, launch, verify links appear for a known device
- [x] T025 Verify SwiftLint passes with no new warnings (`swiftlint lint`)

---

## Post-Implementation Bug Fixes

### Architecture Decode Failure (Critical)

After initial implementation, the "I want one" section never appeared. Root cause: `DeviceHardware.json` contains `architecture: "portduino"` for two devices (RAK6421 Hat+, Elecrow Meshstick 1262), and `portduino` was absent from the `Architecture` Swift enum. This caused `decoder.decode([DeviceHardware].self)` to throw, aborting `refreshBundledDevicesData()` before `importDeviceLinks()` could run.

**Fix**: Changed `DeviceHardware.architecture` from `Architecture` (enum) to `String`. The `Architecture` enum is still used at point-of-use (firmware flashing) via optional binding.

**Android note**: Do not decode `architecture` into a closed/exhaustive enum. Use a string and convert optionally where needed. See `spec.md` → Implementation Notes.

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (bundled file must exist)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (model + migration must exist)
- **User Story 2 (Phase 4)**: Depends on Phase 3 (import logic from US1 is extended)
- **User Story 3 (Phase 5)**: Depends on Phase 2 only (can parallel with US1/US2)
- **Polish (Phase 6)**: Depends on all stories complete

### Parallel Opportunities

```bash
# After Phase 2, these can run in parallel:
# - US1 implementation (T009-T014)
# - US3 directory view (T018-T020) — only needs model, not import logic

# Within US1, tests can run in parallel:
# T006, T007, T008 — all different test functions in same file
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Bundle urls.json
2. Complete Phase 2: Model + migration
3. Complete Phase 3: Import + UI in node info
4. **STOP and VALIDATE**: Verify links appear for known devices
5. Ship as MVP

### Incremental Delivery

1. Setup + Foundational → Schema ready
2. User Story 1 → Links in node info → MVP ✅
3. User Story 2 → Upsert/cleanup → Data stays fresh
4. User Story 3 → Directory view → Full feature
5. Polish → Docs + lint

---

## Notes

- Vendor priority domains (R-003): rakwireless.com, heltec.org, lilygo.cc, seeedstudio.com, elecrow.com → priority 0; rokland.com, hexaspot.com → priority 1; aliexpress.com, amazon.com → priority 2
- Locale preference for regional retailers: check `Locale.current.region?.identifier` — US users see Rokland higher, EU users see Hexaspot higher
- All links stored regardless of device match (FR-007)
- No runtime network fetch in v1 (FR-004)
