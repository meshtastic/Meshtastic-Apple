# Tasks: Automatic Node Database Backup & Restore

**Input**: Design documents from `/specs/011-database-backup-system/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Unit tests are included as the quickstart.md references `NodeBackupManagerTests.swift` and the plan.md project structure includes a test file.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Implementation Update (2026-05-22)

The generated task list below reflects the original file-swap restore design. The working implementation diverged in three important ways:

- Restore no longer swaps active SQLite files or recreates the app `ModelContainer`; it imports entities from a read-only backup container into the existing live container.
- The switch flow now routes the UI back to Connect and clears router selection state before `clearDatabase()` to avoid stale SwiftData model crashes.
- Repeated switch testing also required hardening node and traceroute views against stale or duplicate model identities (`node.num`-based IDs, safe fetches).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization — create files, directories, and shared utilities needed by all user stories

- [X] T001 Create `Meshtastic/Persistence/` directory structure for backup service files
- [X] T002 [P] Add `💾 Backup` Logger category (e.g., `static let backup = Logger(subsystem: subsystem, category: "💾 Backup")`) to the existing `Meshtastic/Extensions/Logger.swift`
- [X] T003 [P] Define `BackupEntry`, `BackupIndex`, and `NodeBackupResult` data types in `Meshtastic/Persistence/BackupModels.swift`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core `NodeBackupManager` service that MUST be complete before any user story integration can begin

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Implement `NodeBackupManaging` protocol in `Meshtastic/Persistence/NodeBackupManaging.swift`
- [X] T005 Implement `NodeBackupManager` core class with singleton setup, backup directory initialization, and index load/save in `Meshtastic/Persistence/NodeBackupManager.swift`
- [X] T006 Implement SHA-256 checksum computation helper in `NodeBackupManager` (private method) for `.sqlite` file integrity verification in `Meshtastic/Persistence/NodeBackupManager.swift`
- [X] T007 Implement `createBackup(forNode:nodeName:)` method with SQLite file copy (`.store`, `.store-wal`, `.store-shm`), checksum generation, index update, and retry-once logic in `Meshtastic/Persistence/NodeBackupManager.swift`
- [X] T008 Implement restore support in `NodeBackupManager` with checksum validation, backup lookup, and retry-once logic. Final implementation uses `restoreFromBackup(forNode:into:)` to import entities into the live container rather than replacing store files.
- [X] T009 [P] Implement `hasBackup(forNode:)`, `listBackups()`, `deleteBackup(forNode:)`, and `totalBackupSize` computed property in `Meshtastic/Persistence/NodeBackupManager.swift`

**Checkpoint**: `NodeBackupManager` is fully functional and can be called by user story integration code

---

## Phase 3: User Story 1 — Automatic Backup on Node Switch (Priority: P1) 🎯 MVP

**Goal**: When a user switches from Node A to Node B, automatically create a backup of Node A's database before clearing it

**Independent Test**: Connect to Node A, accumulate data, connect to Node B. Verify a backup snapshot for Node A is created automatically at `Application Support/NodeBackups/{nodeANum}/Meshtastic.store`

### Tests for User Story 1

- [X] T010 [P] [US1] Write unit test for `createBackup` success case (verify file copy and index update) in `MeshtasticTests/NodeBackupManagerTests.swift`
- [X] T011 [P] [US1] Write unit test for `createBackup` overwrite case (existing backup is replaced) in `MeshtasticTests/NodeBackupManagerTests.swift`
- [X] T012 [P] [US1] Write unit test for `createBackup` failure and retry-once logic in `MeshtasticTests/NodeBackupManagerTests.swift`

### Implementation for User Story 1

- [X] T013 [US1] Integrate backup call in node-switch flow: insert `await NodeBackupManager.shared.createBackup(forNode:nodeName:)` after `flushDebouncedSaves()` and before `clearDatabase()` in `Meshtastic/Views/Connect/Connect.swift`
- [X] T014 [US1] Add toast/indicator feedback for backup result (success indicator, skip warning) in `Meshtastic/Views/Connect/Connect.swift`
- [X] T015 [US1] Add structured logging statements for backup operations using `Logger.backup` within `Meshtastic/Persistence/NodeBackupManager.swift` (Logger category already added in T002)

**Checkpoint**: Switching from Node A to Node B creates a backup file for Node A. Verify with unit tests and manual test.

---

## Phase 4: User Story 2 — Automatic Restore on Reconnection (Priority: P1)

**Goal**: When a user reconnects to a previously backed-up node, automatically restore that node's database state

**Independent Test**: After backing up Node A and connecting to Node B, reconnect to Node A. Verify Node A's data (messages, positions) is restored and visible.

### Tests for User Story 2

- [X] T016 [P] [US2] Write unit test for restore success in `MeshtasticTests/NodeBackupManagerTests.swift`. The final implementation validates import-based restore behavior instead of file replacement/container recreation.
- [X] T017 [P] [US2] Write unit test for `restoreFromBackup(forNode:into:)` with checksum mismatch (corrupt backup detection) in `MeshtasticTests/NodeBackupManagerTests.swift`
- [X] T018 [P] [US2] Write unit test for `restoreFromBackup(forNode:into:)` when no backup exists (returns `.noBackupFound`) in `MeshtasticTests/NodeBackupManagerTests.swift`

### Implementation for User Story 2

- [X] T019 [US2] Integrate restore call in node-connect flow: after routing the UI away from bound models and running `clearDatabase()` + `MeshPackets.recreateShared()`, call `await NodeBackupManager.shared.restoreFromBackup(forNode:into:)` before connection steps in `Meshtastic/Views/Connect/Connect.swift`
- [X] T020 [US2] Handle restore result: log and surface restore/skip outcomes in `Meshtastic/Views/Connect/Connect.swift` without recreating the container again after import restore
- [X] T021 [US2] Add structured logging for restore operations using `Logger.backup` in `Meshtastic/Persistence/NodeBackupManager.swift`

**Checkpoint**: Full round-trip works — switch away from Node A (backup), connect to Node B, reconnect to Node A (restore). Node A data is present.

---

## Phase 5: User Story 3 — Manual Backup Management (Priority: P2)

**Goal**: Provide a Settings UI where users can view existing backups (node name, date, size) and delete ones they no longer need

**Independent Test**: Navigate to Settings → Backup Management. Verify list shows backed-up nodes with metadata. Verify deletion removes backup and frees storage.

### Implementation for User Story 3

- [X] T022 [P] [US3] Create `BackupRowView` displaying node name, backup date, and formatted file size in `Meshtastic/Views/Settings/BackupManagement/BackupRowView.swift`
- [X] T023 [US3] Create `BackupManagementView` with list of backups, total storage display, and swipe-to-delete in `Meshtastic/Views/Settings/BackupManagement/BackupManagementView.swift`
- [X] T024 [US3] Add delete confirmation alert and call `NodeBackupManager.shared.deleteBackup(forNode:)` on confirm in `Meshtastic/Views/Settings/BackupManagement/BackupManagementView.swift`
- [X] T025 [US3] Add navigation link to `BackupManagementView` from the Settings screen in `Meshtastic/Views/Settings/` (appropriate settings file). Acceptance: verify path is Settings → Backup Management (2 taps to list, 3rd tap to delete) satisfying SC-005.

**Checkpoint**: Users can navigate to backup management, see all backups with metadata, and delete individual backups.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, error handling improvements, and cleanup that span multiple user stories

- [X] T026 [P] Handle insufficient storage edge case: check available disk space before backup, return `.skipped(reason:)` with appropriate toast in `Meshtastic/Persistence/NodeBackupManager.swift`
- [X] T027 [P] Handle rapid node-switch edge case: ensure concurrent backup/restore calls are serialized (actor isolation) in `Meshtastic/Persistence/NodeBackupManager.swift`
- [X] T028 [P] Delete corrupt backup files when checksum validation fails during restore in `Meshtastic/Persistence/NodeBackupManager.swift`
- [X] T029 Handle app termination mid-backup: verify backup index consistency on launch and clean up orphaned files in `Meshtastic/Persistence/NodeBackupManager.swift`
- [X] T030 Run SwiftLint on all new files and fix any violations
- [X] T031 Validate implementation against quickstart.md scenarios (build + manual test)
- [X] T032 [P] Verify SC-004 (non-blocking UI): assert that file I/O in `NodeBackupManager` runs via `Task.detached` off `@MainActor`, and add a unit test confirming backup/restore do not execute on the main thread in `MeshtasticTests/NodeBackupManagerTests.swift`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (T001–T003) — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion
- **User Story 2 (Phase 4)**: Depends on Phase 2 completion; logically follows US1 (backup must exist to restore) but code is independently implementable
- **User Story 3 (Phase 5)**: Depends on Phase 2 completion (needs `listBackups()`, `deleteBackup()`)
- **Polish (Phase 6)**: Depends on Phases 3–5 being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 — no dependencies on other stories
- **User Story 2 (P1)**: Can start after Phase 2 — independent of US1 at code level (but integration testing benefits from US1 being done)
- **User Story 3 (P2)**: Can start after Phase 2 — fully independent of US1/US2

### Within Each User Story

- Tests written FIRST, verified to FAIL before implementation
- Integration hooks depend on `NodeBackupManager` core methods (Phase 2)
- Toast/logging tasks depend on integration hooks being in place

### Parallel Opportunities

- **Phase 1**: T002 and T003 can run in parallel (different files)
- **Phase 2**: T009 can run in parallel with T005–T008 (different methods, read-only index access)
- **Phase 3**: T010, T011, T012 can all run in parallel (independent test cases)
- **Phase 4**: T016, T017, T018 can all run in parallel (independent test cases)
- **Phase 5**: T022 can run in parallel with other Phase 5 tasks (standalone view component)
- **Phase 6**: T026, T027, T028 can all run in parallel (independent edge cases)

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Write unit test for createBackup success case in MeshtasticTests/NodeBackupManagerTests.swift"
Task: "Write unit test for createBackup overwrite case in MeshtasticTests/NodeBackupManagerTests.swift"
Task: "Write unit test for createBackup failure and retry-once logic in MeshtasticTests/NodeBackupManagerTests.swift"
```

## Parallel Example: User Story 3

```bash
# BackupRowView has no dependency on BackupManagementView:
Task: "Create BackupRowView in Meshtastic/Views/Settings/BackupManagement/BackupRowView.swift"
# Then BackupManagementView uses BackupRowView:
Task: "Create BackupManagementView in Meshtastic/Views/Settings/BackupManagement/BackupManagementView.swift"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Setup (T001–T003)
2. Complete Phase 2: Foundational (T004–T009) — CRITICAL, blocks all stories
3. Complete Phase 3: User Story 1 — Backup on switch
4. Complete Phase 4: User Story 2 — Restore on reconnect
5. **STOP and VALIDATE**: Test full round-trip backup/restore cycle
6. Deploy/demo if ready — this is the MVP

### Incremental Delivery

1. Setup + Foundational → Core service ready
2. Add User Story 1 → Backups happen automatically (MVP part 1)
3. Add User Story 2 → Restore happens automatically (MVP complete!)
4. Add User Story 3 → Management UI for power users
5. Polish phase → Edge cases and cleanup

### Parallel Team Strategy

With multiple developers after Phase 2 completes:

- Developer A: User Story 1 (backup integration)
- Developer B: User Story 2 (restore integration)
- Developer C: User Story 3 (management UI)

All stories integrate independently into the shared `NodeBackupManager`.

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- The database contains only one node's data at a time — backup is a full SQLite file copy
- `NodeBackupManager` is `@MainActor`-isolated; file I/O runs on background thread via `Task.detached`
- Backup is an async await barrier: `clearDatabase()` is suspended (not thread-blocking) until backup completes via `await`
- One backup per node (1:1 mapping) — new backups overwrite previous ones
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
