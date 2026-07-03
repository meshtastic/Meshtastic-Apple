# Backup Service API Contract

**Feature**: 011-database-backup-system
**Date**: 2025-07-14
**Type**: Internal Swift API (no external network interface)

## Overview

The backup system is an internal service with no external-facing APIs. It exposes a Swift API consumed by the connection lifecycle within the app. This document defines the public interface contract for `NodeBackupManager`.

## NodeBackupManager Protocol

```swift
/// Public contract for the node database backup/restore service.
/// All methods are async and safe to call from any actor context.
@MainActor
protocol NodeBackupManaging: Sendable {

    /// Creates a backup of the current database state for the specified node.
    ///
    /// - Parameters:
    ///   - nodeNum: The unique node number (`NodeInfoEntity.num`) to associate with the backup
    ///   - nodeName: Optional display name for the node (for UI purposes)
    /// - Returns: Result indicating success or skip reason
    /// - Note: Retries once automatically on failure before returning `.skipped`
    func createBackup(forNode nodeNum: Int64, nodeName: String?) async -> NodeBackupResult

    /// Restores a full backup by importing all entities from a backup snapshot into the live container.
    /// Call this after `clearDatabase()` has emptied the active store.
    ///
    /// - Parameters:
    ///   - nodeNum: The node number whose backup should be imported
    ///   - container: The live container to import into
    /// - Note: Validates the stored `.store` checksum before importing. Corrupt backups are deleted.
    func restoreFromBackup(forNode nodeNum: Int64, into container: ModelContainer) async -> NodeBackupResult

    /// Checks whether a backup exists for the specified node.
    ///
    /// - Parameter nodeNum: The node number to check
    /// - Returns: `true` if a valid backup entry exists in the index
    func hasBackup(forNode nodeNum: Int64) -> Bool

    /// Returns metadata for all existing backups.
    ///
    /// - Returns: Array of backup entries sorted by most recent first
    func listBackups() -> [BackupEntry]

    /// Deletes the backup for the specified node, freeing storage.
    ///
    /// - Parameter nodeNum: The node number whose backup should be deleted
    /// - Returns: `true` if backup was found and deleted, `false` if no backup existed
    @discardableResult
    func deleteBackup(forNode nodeNum: Int64) -> Bool

    /// Returns the total disk space consumed by all backups in bytes.
    var totalBackupSize: Int64 { get }
}
```

## Integration Points

### Backup Trigger (in node-switch flow)

```swift
// Called in Connect.swift before clearDatabase()
// Pseudo-code showing integration contract:

let currentNodeNum = accessoryManager.activeDeviceNum
let currentNodeName = /* fetch from NodeInfoEntity if available */

// 1. Flush pending writes
await MeshPackets.shared.flushDebouncedSaves()

// 2. Create backup (synchronous gate — blocks until complete)
let backupResult = await NodeBackupManager.shared.createBackup(
    forNode: currentNodeNum,
    nodeName: currentNodeName
)

// 3. Show toast if needed
switch backupResult {
case .success(let entry):
    Logger.backup.info("Backed up node \(entry.nodeNum)")
case .skipped(let reason):
    showToast("Backup skipped: \(reason)")
case .noBackupFound:
    break // Should not occur for create
}

// 4. Proceed with clear
await MeshPackets.shared.clearDatabase(includeRoutes: false)
MeshPackets.recreateShared()
```

### Restore Trigger (in node-connect flow)

```swift
// Called after UI state is detached from live model objects,
// after clearDatabase + recreateShared, and before connection steps begin
// Pseudo-code showing integration contract:

let resolvedTargetNodeNum = await NodeBackupManager.shared.resolveNodeNum(forPeripheralId: device.id.uuidString)
let targetNodeNum = device.num ?? resolvedTargetNodeNum

// 1. Attempt restore
let restoreResult = await NodeBackupManager.shared.restoreFromBackup(
    forNode: targetNodeNum,
    into: PersistenceController.shared.container
)

// 2. Handle restore result
switch restoreResult {
case .success(let entry):
    showToast("Restored \(entry.nodeName ?? "node") data")
case .skipped(let reason):
    Logger.backup.warning("Restore skipped: \(reason)")
    showToast("Could not restore backup")
case .noBackupFound:
    Logger.backup.debug("No backup for node \(targetNodeNum)")
}

// 3. Proceed with connection steps
```

## Error Handling Contract

| Scenario | Behavior | User Feedback |
|----------|----------|---------------|
| Backup succeeds | Proceed normally | Brief success indicator (optional) |
| Backup fails, retry succeeds | Proceed normally | None |
| Backup fails twice | Skip, proceed with connection | Non-blocking toast: "Backup skipped" |
| Restore succeeds | Import entities into live container, proceed | Toast: "Restored {nodeName} data" |
| Restore checksum mismatch | Skip, delete corrupt backup | Toast: "Could not restore backup" |
| Restore fails twice | Skip, proceed normally | Toast: "Could not restore backup" |
| Insufficient storage | Skip backup with reason | Toast: "Not enough storage for backup" |

## Thread Safety Guarantees

- `NodeBackupManager` is `@MainActor`-isolated for state consistency
- File I/O operations run on a background thread via `Task.detached` with `.userInitiated` priority
- Restore import helpers can be `nonisolated` so they can execute from detached tasks while the manager itself remains `@MainActor`
- All public methods are `async` — callers must `await` to ensure ordering
- The backup index file is accessed exclusively through the manager (no concurrent writes)
