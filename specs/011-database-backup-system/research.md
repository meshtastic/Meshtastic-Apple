# Research: Automatic Node Database Backup & Restore

**Feature**: 011-database-backup-system  
**Date**: 2025-07-14  
**Status**: Complete

## Research Questions & Findings

### R1: SQLite File Copy Safety with SwiftData

**Question**: How to safely copy the SQLite backing store while SwiftData/ModelContainer is active?

**Decision**: Use a two-phase approach — flush pending writes via `modelContext.save()`, then close the `ModelContainer` (or use SQLite's `VACUUM INTO` for a hot copy), then perform `FileManager.copyItem(at:to:)` on the `.sqlite`, `.sqlite-wal`, and `.sqlite-shm` files.

**Rationale**: SwiftData uses SQLite with WAL mode. Copying without flushing WAL risks incomplete data. The safest approach is:
1. Call `modelContext.save()` to flush pending changes
2. Use `sqlite3_file_control` with `SQLITE_FCNTL_PERSIST_WAL` or simply checkpoint the WAL before copying
3. Alternatively, since the app already calls `clearDatabase()` after backup, we can tear down the `ModelContainer`, copy the files, then recreate the container for the new node

Since `MeshPackets.recreateShared()` already destroys and recreates the model actor, and the existing flow calls `clearDatabase` followed by `MeshPackets.recreateShared()`, we can insert the file copy between `flushDebouncedSaves()` and `clearDatabase()`.

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
- Files: `Meshtastic.sqlite`, `Meshtastic.sqlite-wal`, `Meshtastic.sqlite-shm` per node subfolder

**Alternatives considered**:
- Documents directory — visible in Files app, inappropriate for internal data
- Caches directory — may be purged by system, unacceptable for backups
- Temporary directory — not persistent
- iCloud container — spec explicitly says local-only unless decided otherwise

### R3: Backup Integrity Verification

**Question**: How to detect backup corruption and ensure integrity (FR-007)?

**Decision**: Use SHA-256 checksum of the `.sqlite` file stored in the metadata index. On restore, recompute and compare before proceeding.

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
- The backup index must be accessible *before* any `ModelContainer` is initialized (to decide whether to restore)
- Using SwiftData for metadata would create a chicken-and-egg problem: the container might need to be replaced during restore
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

**Decision**: Check for existing backup in the connection sequence after the `ModelContainer` is initialized but before the device starts sending data. Specifically, after `clearDatabase` + `MeshPackets.recreateShared()`, check the backup index for the target node number and, if found, replace the SQLite files before the actor begins processing packets.

**Rationale**:
- The restore must happen *after* clearing (to have a fresh slate) but *before* new data arrives
- The connection flow uses `SequentialSteps` with 8 steps — restore fits between container recreation and step 1
- After replacing files, the `ModelContainer` must be re-initialized to pick up the restored data
- Flow: clear old → recreate container → check backup exists → if yes: copy backup files over → recreate container again → proceed with connection

**Alternatives considered**:
- Restore before clear — would mix old node data with restored data if same container
- Restore during `AccessoryManager.connect()` — too late, packets may have arrived
- Lazy restore on first query — complex, risks partial state

### R7: Concurrency & Thread Safety

**Question**: How to ensure backup/restore doesn't block the UI and handles concurrent access safely?

**Decision**: Run file operations on a detached `Task` with `.userInitiated` priority, wrapped in a `@MainActor`-isolated async method that awaits completion. Use `await` at the call site to block the logical flow without blocking the UI thread.

**Rationale**:
- Swift Concurrency's structured concurrency ensures the backup completes before `clearDatabase` proceeds
- `FileManager` operations are synchronous but fast (file copy, not network I/O)
- For databases up to 50MB, copy takes < 1 second on modern devices
- The `@MainActor` isolation of `AccessoryManager` and `PersistenceController` means we need to hop off main for the file I/O

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
