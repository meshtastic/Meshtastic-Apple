# Quickstart: Automatic Node Database Backup & Restore

**Feature**: 011-database-backup-system
**Date**: 2025-07-14

## Overview

This feature adds automatic SQLite file-level backup and import-based restore when switching between Meshtastic nodes. The database only ever contains one node's data at a time, so a full file copy is used for backup creation, while restore imports entities from that snapshot into the existing live SwiftData container.

## Key Decisions

| Decision | Choice | Reference |
|----------|--------|-----------|
| Backup approach | SQLite file copy (`.store` + WAL/SHM) | research.md R1 |
| Restore approach | Open backup read-only and import entities into the live container | research.md R6 |
| Storage location | `Application Support/NodeBackups/{nodeNum}/` | research.md R2 |
| Integrity check | SHA-256 checksum of `.store` file | research.md R3 |
| Metadata format | JSON file (`backup-index.json`) | research.md R4 |
| Hook point | After `flushDebouncedSaves()`, before `clearDatabase()` | research.md R5 |
| Restore point | After routing UI away from bound models, clearing DB, and recreating `MeshPackets`, before connection steps | research.md R6 |
| Concurrency | `async`/`await` with background file I/O | research.md R7 |
| Error handling | Retry once, then skip with toast | research.md R8 |

## Architecture at a Glance

```
┌──────────────────────────────────────────────────────────────────┐
│                         Connect.swift                             │
│  (User taps "Connect to Node B" while connected to Node A)       │
└───────────────────────────────┬──────────────────────────────────┘
                                │
                                v
┌──────────────────────────────────────────────────────────────────┐
│  1. flushDebouncedSaves()                                        │
│  2. NodeBackupManager.createBackup(forNode: nodeA)  ◄── NEW      │
│  3. Resolve target node number (device.num or peripheralId)       │
│  4. Disconnect current radio                                      │
│  5. Route UI back to Connect / clear selected model state         │
│  6. clearDatabase(includeRoutes: false)                           │
│  7. MeshPackets.recreateShared()                                  │
│  8. restoreFromBackup(forNode: nodeB, into: liveContainer)        │
│  9. Connect to Node B                                             │
└──────────────────────────────────────────────────────────────────┘
```

## File Structure

```
Meshtastic/
├── Persistence/
│   └── NodeBackupManager.swift       # Core service (backup, restore, index)
├── Extensions/
│   └── Logger+Backup.swift           # Logger.backup category
├── Views/Settings/BackupManagement/
│   ├── BackupManagementView.swift    # Settings → Backup Management list
│   └── BackupRowView.swift           # Row showing node name, date, size
└── Views/Connect/Connect.swift       # Modified: insert backup/restore calls

MeshtasticTests/
└── NodeBackupManagerTests.swift      # Unit tests (in-memory container)
```

## Development Commands

```bash
# Build the project (requires Xcode & macOS)
xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 16' test

# Lint
swiftlint lint --config .swiftlint.yml
```

## Implementation Order

1. **Logger extension** — Add `.backup` category to `Logger.swift`
2. **Data types** — `BackupEntry`, `BackupIndex`, `NodeBackupResult` structs
3. **NodeBackupManager** — Core service with file copy, checksum, index management
4. **Integration hooks** — Modify `Connect.swift` to call backup/restore
5. **Backup Management UI** — Settings screen for viewing/deleting backups
6. **Tests** — Unit tests for manager logic (mock FileManager or use temp directories)

## Gotchas & Notes

- **WAL checkpoint**: Before copying, consider calling `modelContext.save()` to flush WAL. The existing `flushDebouncedSaves()` call handles this.
- **Container recreation**: The working implementation does **not** recreate or replace the app's `ModelContainer` during restore. Recreating the container caused stale-model crashes in SwiftData.
- **UI safety before clear**: Route the app back to Connect and clear router selection state before `clearDatabase()` so views do not hold deleted model objects.
- **Stable list identity**: Views that render `NodeInfoEntity` collections should prefer `node.num` over `\.self` and tolerate duplicate transient models during repeated switch cycles.
- **File size**: Typical Meshtastic databases are 1–10MB. Copy operations complete in <1 second.
- **No schema migration needed**: Backups are always the same schema version as the running app (same binary creates and restores them).
- **First-time connect**: No backup exists → no restore → proceeds normally (FR-006).
