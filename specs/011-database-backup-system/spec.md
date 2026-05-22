# Feature Specification: Automatic Node Database Backup & Restore

**Feature Branch**: `copilot/spec-database-backup-system`  
**Created**: 2025-07-14  
**Status**: Draft  
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
- How does the system handle a node whose number has changed (factory reset)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST automatically create a backup of the current node's database state when the user initiates a connection to a different node.
- **FR-002**: The system MUST automatically restore a previously backed-up database state when the user reconnects to a node that has an existing backup.
- **FR-003**: The system MUST identify nodes uniquely to associate backups correctly.
- **FR-004**: The system MUST handle backup failures gracefully without blocking the node switch.
- **FR-005**: The system MUST provide a UI for viewing and managing existing backups.
- **FR-006**: The system MUST handle the case where no backup exists for a connecting node (proceed normally).
- **FR-007**: The system MUST ensure data integrity of backups (detect corruption).

### Key Entities

- **NodeBackup**: A snapshot of a node's database state. Attributes: node identifier, creation timestamp, size, integrity checksum, file path.
- **BackupMetadata**: Index of all backups. Attributes: node identifier, node display name, last backup date, backup file reference.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Backup creation completes within 5 seconds for a database with up to 10,000 entities.
- **SC-002**: Restore completes within 5 seconds for a database with up to 10,000 entities.
- **SC-003**: Zero data loss when switching between two previously connected nodes in round-trip testing.
- **SC-004**: Backup/restore operations do not block the UI thread.
- **SC-005**: Users can manage backups and free storage within 3 taps from Settings.

## Assumptions

- The app uses SwiftData exclusively for persistence (per project convention).
- Each node is uniquely identifiable by its node number (`num` field on `NodeInfoEntity`).
- The existing `PersistenceController` manages a single `ModelContainer` shared across the app.
- Backups are stored locally on-device (not synced to iCloud unless explicitly decided).
- The user typically connects to a small number of nodes (2–5) rather than dozens.
- **The database contains only one node's data at a time** — the app clears previous node data before connecting to a new node. This means backup is a full SQLite file snapshot (not per-node filtered extraction).

## Clarifications

### Session 2026-05-22

- Q: What is the backup granularity — full database snapshot or per-node filtered data? → A: Full SQLite file snapshot (the DB only ever contains one node's data at a time; it clears previous node data before connecting a new one).
