# Data Model: Automatic Node Database Backup & Restore

**Feature**: 011-database-backup-system  
**Date**: 2025-07-14

## Entities

### BackupEntry (Codable struct — stored in JSON index)

Represents a single node's backup snapshot metadata.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `nodeNum` | `Int64` | Unique node identifier (from `NodeInfoEntity.num`) | Primary key; unique |
| `nodeName` | `String?` | Human-readable node display name at time of backup | Optional; for UI display |
| `createdAt` | `Date` | Timestamp when backup was created | Required |
| `fileSize` | `Int64` | Total size of backup files in bytes | Required; ≥ 0 |
| `checksum` | `String` | SHA-256 hex digest of the `.sqlite` file | Required; 64 chars |
| `backupPath` | `String` | Relative path from `NodeBackups/` to backup directory | Required |

### BackupIndex (Codable struct — root of JSON file)

Top-level container for all backup metadata.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| `version` | `Int` | Schema version of the index format | Required; currently `1` |
| `entries` | `[Int64: BackupEntry]` | Map of node number to backup metadata | Required; may be empty |
| `lastModified` | `Date` | Timestamp of last index modification | Required |

### NodeBackupResult (enum — in-memory only)

Represents the outcome of a backup or restore operation.

| Case | Associated Values | Description |
|------|-------------------|-------------|
| `.success` | `BackupEntry` | Operation completed successfully |
| `.skipped(reason: String)` | `String` | Operation was skipped (no data, failed after retry) |
| `.noBackupFound` | — | No existing backup for the target node |

## Relationships

```
BackupIndex (1) ──contains──> (0..*) BackupEntry

BackupEntry.nodeNum ──references──> NodeInfoEntity.num (external, in SwiftData)

NodeBackups/
├── backup-index.json          (BackupIndex serialized)
├── {nodeNum}/
│   ├── Meshtastic.sqlite      (SQLite database copy)
│   ├── Meshtastic.sqlite-wal  (WAL file, if present)
│   └── Meshtastic.sqlite-shm  (Shared memory file, if present)
```

## Validation Rules

1. **nodeNum uniqueness**: Only one `BackupEntry` per `nodeNum` in the index (enforced by `Dictionary` key)
2. **Checksum format**: Must be a valid 64-character hexadecimal string (SHA-256)
3. **File existence**: `backupPath` must resolve to existing directory containing at least `Meshtastic.sqlite`
4. **Size consistency**: `fileSize` should approximate the actual file sizes on disk (± WAL size variance)
5. **Index version**: Must be `1` (future versions may require migration logic)

## State Transitions

### Backup Lifecycle

```
┌─────────────┐     connect to      ┌──────────────┐    file copy     ┌─────────────┐
│  Connected  │ ──── new node ─────> │   Backing    │ ── succeeds ──> │   Backed    │
│  to Node A  │                      │     Up       │                  │     Up      │
└─────────────┘                      └──────────────┘                  └─────────────┘
                                           │                                  │
                                       fails (retry)                    next switch
                                           │                                  │
                                           v                                  v
                                     ┌──────────────┐               (overwrites previous)
                                     │   Skipped    │
                                     │  (toast)     │
                                     └──────────────┘
```

### Restore Lifecycle

```
┌─────────────┐     connect to      ┌──────────────┐   backup found   ┌─────────────┐
│  Connecting │ ──── Node A ──────> │   Check      │ ── & valid ────> │  Restoring  │
│             │                      │   Index      │                  │             │
└─────────────┘                      └──────────────┘                  └─────────────┘
                                           │                                  │
                                     no backup /                         succeeds
                                     corrupt                                  │
                                           │                                  v
                                           v                           ┌─────────────┐
                                     ┌──────────────┐                  │  Restored   │
                                     │  Proceed     │                  │  (toast)    │
                                     │  Normally    │                  └─────────────┘
                                     └──────────────┘
```

## Storage Layout

```
{App Support}/
└── NodeBackups/
    ├── backup-index.json
    ├── 1234567890/
    │   ├── Meshtastic.sqlite
    │   ├── Meshtastic.sqlite-wal
    │   └── Meshtastic.sqlite-shm
    ├── 9876543210/
    │   ├── Meshtastic.sqlite
    │   └── (WAL/SHM may not exist if checkpointed)
    └── ...
```

## Swift Type Definitions (Preview)

```swift
struct BackupEntry: Codable, Sendable {
    let nodeNum: Int64
    var nodeName: String?
    var createdAt: Date
    var fileSize: Int64
    var checksum: String
    var backupPath: String
}

struct BackupIndex: Codable, Sendable {
    var version: Int = 1
    var entries: [Int64: BackupEntry] = [:]
    var lastModified: Date = .now
}

enum NodeBackupResult: Sendable {
    case success(BackupEntry)
    case skipped(reason: String)
    case noBackupFound
}
```
