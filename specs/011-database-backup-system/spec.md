# Feature Specification: Automatic Node Database Backup & Restore

**Feature Branch**: `copilot/spec-database-backup-system`
**Created**: 2025-07-14
**Status**: Implemented
**Input**: User description: "Automatically back up the database of the currently connected node when connecting to another node, and automatically restore the backup when a user connects to a previously connected node again."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Automatic Backup on Node Switch (Priority: P1)

A user is connected to Node A and has accumulated messages, telemetry, positions, and node info data. When they connect to Node B, the app automatically creates a backup of Node A's database state before loading Node B's data. This happens transparently without user intervention.

**Why this priority**: This is the core value proposition — preserving per-node data that would otherwise be lost or mixed when switching between nodes. Without backup, the feature has no purpose.

**Independent Test**: Connect to Node A, receive some messages and telemetry, then connect to Node B. Verify that a backup file/snapshot for Node A is created automatically and contains the correct data.

**Acceptance Scenarios**:

1. **Given** the user is connected to Node A with accumulated data, **When** they initiate a connection to Node B, **Then** the app creates a backup snapshot of Node A's data before the connection switches.
2. **Given** a backup is being created, **When** the backup completes, **Then** a success indicator is briefly shown and the connection to the new node proceeds.
3. **Given** a backup already exists for Node A, **When** the user switches away from Node A again, **Then** the previous backup is replaced with the new, more recent backup.

---

### User Story 2 — Automatic Restore on Reconnection (Priority: P1)

A user who previously connected to Node A (and whose data was backed up) now reconnects to Node A. The app detects the prior backup and automatically restores it, bringing back the user's messages, positions, telemetry, and node list from when they were last connected.

**Why this priority**: This completes the round-trip — backup is useless without restore. Together with P1 backup, this forms the MVP.

**Independent Test**: After backing up Node A and connecting to Node B, reconnect to Node A. Verify that Node A's previously backed-up data is restored and visible.

**Acceptance Scenarios**:

1. **Given** a backup exists for Node A, **When** the user connects to Node A, **Then** the app restores Node A's backed-up data automatically.
2. **Given** restore is in progress, **When** the restore completes, **Then** the UI reflects the restored data (messages, node list, positions).
3. **Given** no backup exists for a node, **When** the user connects to that node, **Then** the app proceeds normally without any restore attempt.

---

### User Story 3 — Manual Backup Management (Priority: P2)

A user wants to see which node backups exist, how much space they consume, and optionally delete old backups they no longer need.

**Why this priority**: Power users and users with limited storage need visibility and control over backup data. Not required for MVP but important for usability.

**Independent Test**: Navigate to backup management UI, verify list shows previously backed-up nodes with metadata (date, size), and verify deletion removes the backup.

**Acceptance Scenarios**:

1. **Given** backups exist for multiple nodes, **When** the user navigates to backup management, **Then** a list shows each backup with node name, date, and size.
2. **Given** the user selects a backup to delete, **When** they confirm deletion, **Then** the backup is removed and storage is freed.

---

### Edge Cases

- What happens if the app is terminated mid-backup?
- What happens if the backup file becomes corrupted?
- How does the system handle connecting to a node when device storage is critically low?
- What happens if the user connects rapidly between multiple nodes?
- How does the system handle a node whose number has changed (factory reset)? → Decision: A new node number is treated as a new node. The node number does not currently change on factory reset, but if it does in the future, the old backup remains accessible under the old number and the new number starts fresh.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST automatically create a backup of the current node's database state when the user initiates a connection to a different node.
- **FR-002**: The system MUST automatically restore a previously backed-up database state when the user reconnects to a node that has an existing backup, without replacing the live `ModelContainer`.
- **FR-003**: The system MUST identify nodes uniquely to associate backups correctly.
- **FR-004**: The system MUST retry a failed backup/restore once automatically; if the retry also fails, skip with a non-blocking toast warning and proceed with the node connection.
- **FR-005**: The system MUST provide a UI for viewing and managing existing backups.
- **FR-006**: The system MUST handle the case where no backup exists for a connecting node (proceed normally).
- **FR-007**: The system MUST ensure data integrity of backups (detect corruption).

### Key Entities

- **NodeBackup**: A snapshot of a node's database state. Attributes: node identifier, creation timestamp, size, integrity checksum, file path.
- **BackupMetadata**: Index of all backups. Attributes: node identifier, node display name, last backup date, backup file reference.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Backup creation completes within 5 seconds for a database with up to 10,000 total rows across all entity types (or ~50MB file size).
- **SC-002**: Restore completes within 5 seconds for a database with up to 10,000 total rows across all entity types (or ~50MB file size).
- **SC-003**: Zero data loss when switching between two previously connected nodes in round-trip testing.
- **SC-004**: Backup/restore operations do not block the UI thread.
- **SC-005**: Users can manage backups and free storage within 3 taps from Settings.

## Assumptions

- The app uses SwiftData exclusively for persistence (per project convention).
- Each node is uniquely identifiable by its node number (`num` field on `NodeInfoEntity`).
- The existing `PersistenceController` manages a single `ModelContainer` shared across the app.
- The working implementation keeps that shared `ModelContainer` alive during radio switches and restores data by importing backup contents into the live store after `clearDatabase()`.
- Backups are stored locally on-device (not synced to iCloud unless explicitly decided).
- The user typically connects to a small number of nodes (2–5) rather than dozens.
- **The database contains only one node's data at a time** — the app clears previous node data before connecting to a new node. This means backup is a full SQLite file snapshot (not per-node filtered extraction).

## Clarifications

### Session 2026-05-22

1. **Backup scope** — Q: What is the backup granularity — full database snapshot or per-node filtered data? → A: Full SQLite/SwiftData file snapshot. The DB only ever contains one node's data at a time (previous node data is cleared before connecting a new one).

2. **Backup trigger** — Q: When exactly does the backup happen relative to the node-switch flow? → A: Immediately before the DB is cleared for the new node connection. The clear is suspended via `await` until the snapshot completes (async await barrier — non-blocking to the UI thread).

3. **Retention policy** — Q: How many backups are kept per node? → A: One (1:1 node-to-backup mapping). Each new backup for a given node replaces the previous one.

4. **Restore UX** — Q: How is the user informed when a restore happens? → A: Fully automatic and silent. A brief non-blocking toast/indicator is shown (e.g., "Restored Node A data") but no user action is required.

5. **Error handling** — Q: What happens when a backup or restore operation fails? → A: Retry once automatically. If the retry also fails, silently skip with a brief toast warning; the node connection proceeds regardless. Failed backups will be retried on the next node switch.

6. **Restore mechanism** — Q: Does restore replace the active SQLite files or recreate the app's `ModelContainer`? → A: No. The working implementation opens the backup as a read-only SwiftData container and imports all entities into the already-live container after the database is cleared.

7. **Switch safety** — Q: How does the implementation avoid SwiftData crashes while clearing the current radio's data? → A: The switch flow first navigates the UI back to the Connect tab and clears router selection state so views stop holding stale model references before `clearDatabase()` runs.

8. **Target node lookup** — Q: What if the selected device has no `device.num` yet when switching back? → A: The switch flow resolves the target node number from backup metadata using the stored `peripheralId` before clearing the database.
