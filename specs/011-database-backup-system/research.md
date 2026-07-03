# Research: Automatic Node Database Backup & Restore

**Feature**: 011-database-backup-system
**Date**: 2025-07-14
**Status**: Complete

## Research Questions & Findings

### R1: Backup File Copy Safety with SwiftData

**Question**: How to safely create a backup copy of the SwiftData backing store while SwiftData/ModelContainer is active?

**Decision**: For backup creation, flush pending writes via `flushDebouncedSaves()` and `modelContext.save()`, then copy the `.store`, `.store-wal`, and `.store-shm` files with `FileManager`. Do not apply the same file-swap approach to restore.

**Rationale**: SwiftData uses SQLite with WAL mode. Copying without flushing WAL risks incomplete data. The working backup approach is:
1. Call `modelContext.save()` to flush pending changes
2. Copy the active `.store`, `.store-wal`, and `.store-shm` files into `NodeBackups/{nodeNum}/`
3. Treat the copied store as a snapshot artifact that will later be opened read-only for import

The abandoned restore approaches were:
- swapping SQLite files while the active container still held file descriptors
- recreating the app `ModelContainer` and forcing the UI to rebind

Both produced more aggressive SwiftData crashes than the original problem.

**Alternatives considered**:
- `NSPersistentStoreCoordinator` migration API — not available for SwiftData
- SwiftData `ModelContainer` export API — does not exist in current SDK
- `VACUUM INTO 'path'` — requires raw SQLite access; adds complexity but is atomic
- File coordination (`NSFileCoordinator`) — overkill for single-process app

### R2: Backup Storage Location

**Question**: Where should backup files be stored on-device?

**Decision**: Store in `Application Support/NodeBackups/{nodeNum}/` directory.

**Rationale**:
- `Application Support` is the standard iOS location for app-generated data files that are not user-visible documents
- It is included in device backups (iTunes/Finder) and excluded from iCloud by default
- Organizing by node number creates a clean 1:1 mapping structure
- Files: `Meshtastic.store`, `Meshtastic.store-wal`, `Meshtastic.store-shm` per node subfolder

**Alternatives considered**:
- Documents directory — visible in Files app, inappropriate for internal data
- Caches directory — may be purged by system, unacceptable for backups
- Temporary directory — not persistent
- iCloud container — spec explicitly says local-only unless decided otherwise

### R3: Backup Integrity Verification

**Question**: How to detect backup corruption and ensure integrity (FR-007)?

**Decision**: Use SHA-256 checksum of the `.store` file stored in the metadata index. On restore, recompute and compare before proceeding.

**Rationale**:
- SHA-256 is fast enough for files up to 50MB (< 100ms on modern Apple silicon)
- Detects bit rot, incomplete copies, or filesystem corruption
- Stored in the metadata index alongside other backup info
- If checksum fails on restore, treat as "no backup exists" and proceed normally with a warning toast

**Alternatives considered**:
- SQLite `PRAGMA integrity_check` — slower, more thorough but may take seconds on large DBs
- CRC32 — faster but weaker collision resistance
- No verification — unacceptable per FR-007
- Both checksum + integrity_check — overkill for the use case; checksum is sufficient

### R4: Metadata Storage Format

**Question**: How to track which backups exist and their metadata (node name, date, size)?

**Decision**: Use a JSON file (`backup-index.json`) in the `NodeBackups/` directory.

**Rationale**:
- A JSON file is simple, human-readable, and doesn't require the SwiftData container to be active to read
- The backup index must be accessible before opening any backup snapshot for restore
- Using SwiftData for metadata would create an unnecessary second persistence system for simple file metadata
- `Codable` struct maps cleanly to JSON with minimal code

**Alternatives considered**:
- Separate SwiftData store for metadata — adds complexity, second ModelContainer
- UserDefaults — not appropriate for structured data with variable size
- Property list (plist) — functionally equivalent to JSON but less tooling-friendly
- Core Data (separate store) — unnecessary given simple data structure

### R5: Connection Lifecycle Hook Point

**Question**: Where exactly in the connection flow should backup be triggered?

**Decision**: Insert backup logic in `Connect.swift` (and any other call sites) immediately after `flushDebouncedSaves()` and before `clearDatabase(includeRoutes: false)`. This is the existing "switch node" code path at lines 610–616 and 696–702.

**Rationale**:
- The spec states backup must happen "immediately before the DB is cleared for the new node connection"
- The existing code path is: disconnect → flush → clear → recreate → connect new
- The backup must be synchronous (blocking) per spec: "The clear is blocked until the snapshot completes"
- `AccessoryManager.activeDeviceNum` provides the current node number for backup identification

**Alternatives considered**:
- Hook in `AccessoryManager+Connect.swift` — would work but the clear/recreate calls live in `Connect.swift` view code
- Background async backup — violates spec requirement that clear is blocked until snapshot completes
- Notification-based trigger — too loosely coupled, timing not guaranteed

### R6: Restore Trigger & Flow

**Question**: How and when does restore happen during connection?

**Decision**: Check for an existing backup in the node-switch sequence after the app has navigated away from model-bound views and after `clearDatabase` + `MeshPackets.recreateShared()`. If a backup exists, open it as a read-only `ModelContainer` and import all entities into the already-live container before the new connection begins processing packets.

**Rationale**:
- The restore must happen *after* clearing (to have a fresh slate) but *before* new data arrives
- Keeping the same app `ModelContainer` avoids SwiftData "destroyed backing data" failures during repeated switches
- Importing from a read-only backup container preserves full historical entities the radio will not resend, such as messages, trace routes, telemetry history, and waypoints
- Flow: backup current node → disconnect → route UI away from bound models → clear live DB → recreate `MeshPackets` → import target backup into live container → connect new radio

**Alternatives considered**:
- Restore by swapping SQLite files under the live store — unsafe with an active SwiftData container
- Restore by recreating the app `ModelContainer` and forcing `.id()`-based UI teardown — caused stale model crashes
- Restore during `AccessoryManager.connect()` — too late, packets may have arrived

### R7: Concurrency & Thread Safety

**Question**: How to ensure backup/restore doesn't block the UI and handles concurrent access safely?

**Decision**: Run file operations on a detached `Task` with `.userInitiated` priority, wrapped in a `@MainActor`-isolated async method that awaits completion. Use `await` at the call site to block the logical flow without blocking the UI thread.

**Rationale**:
- Swift Concurrency's structured concurrency ensures the backup completes before `clearDatabase` proceeds
- `FileManager` operations are synchronous but fast (file copy, not network I/O)
- For databases up to 50MB, copy takes < 1 second on modern devices
- The `@MainActor` isolation of `AccessoryManager` and `PersistenceController` means we need to hop off main for the file I/O
- Restore helper methods that read from backup snapshots must be `nonisolated` when called from detached tasks

**Alternatives considered**:
- `DispatchQueue.global().async` — old-style, doesn't integrate with Swift Concurrency
- `Task.detached` without awaiting — violates the "synchronous gate" requirement
- Running on main thread — would block UI for large databases

### R8: Error Handling & Retry Strategy

**Question**: How to implement the retry-once-then-skip error handling (FR-004)?

**Decision**: Wrap backup/restore in a `do/catch` with a single retry. On second failure, log the error and return a `.skipped` result that triggers a toast notification.

**Rationale**:
- Spec: "Retry once automatically. If the retry also fails, skip with a non-blocking toast warning"
- The connection must never be blocked by backup failures — user experience takes priority
- Failed backups are not catastrophic — they'll be retried on the next node switch
- Toast notifications use the existing app notification system

**Alternatives considered**:
- Exponential backoff — overkill for a file copy operation
- User-prompted retry — violates the "transparent" requirement
- No retry — spec explicitly requires one retry attempt
