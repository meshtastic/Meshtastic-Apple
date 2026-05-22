# Quickstart: Automatic Node Database Backup & Restore

**Feature**: 011-database-backup-system  
**Date**: 2025-07-14

## Overview

This feature adds automatic SQLite file-level backup and restore when switching between Meshtastic nodes. The database only ever contains one node's data at a time, so a full file copy is both simple and complete.

## Key Decisions

| Decision | Choice | Reference |
|----------|--------|-----------|
| Backup approach | SQLite file copy (`.sqlite` + WAL/SHM) | research.md R1 |
| Storage location | `Application Support/NodeBackups/{nodeNum}/` | research.md R2 |
| Integrity check | SHA-256 checksum of `.sqlite` file | research.md R3 |
| Metadata format | JSON file (`backup-index.json`) | research.md R4 |
| Hook point | After `flushDebouncedSaves()`, before `clearDatabase()` | research.md R5 |
| Restore point | After clear + recreate, before connection steps | research.md R6 |
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
│  3. clearDatabase(includeRoutes: false)                           │
│  4. MeshPackets.recreateShared()                                  │
│  5. NodeBackupManager.restoreBackup(forNode: nodeB) ◄── NEW      │
│  6. MeshPackets.recreateShared() (if restore succeeded)           │
│  7. Connect to Node B                                             │
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
- **Container recreation**: After replacing SQLite files, `MeshPackets.recreateShared()` must be called to re-initialize the `ModelContainer` with new data.
- **File size**: Typical Meshtastic databases are 1–10MB. Copy operations complete in <1 second.
- **No schema migration needed**: Backups are always the same schema version as the running app (same binary creates and restores them).
- **First-time connect**: No backup exists → no restore → proceeds normally (FR-006).
