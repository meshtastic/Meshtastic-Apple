# Implementation Plan: Automatic Node Database Backup & Restore

**Branch**: `011-database-backup-system` | **Date**: 2025-07-14 | **Spec**: `specs/011-database-backup-system/spec.md`
**Input**: Feature specification from `/specs/011-database-backup-system/spec.md`

## Summary

Implement an automatic database backup and restore system that snapshots the SQLite/SwiftData store file when switching between Meshtastic nodes, and restores a previous snapshot when reconnecting to a previously-used node. The approach uses direct SQLite file copy (via `FileManager`) since the database contains only one node's data at a time, with backup metadata tracked in a lightweight plist/JSON index. Integration hooks into the existing `AccessoryManager` connection lifecycle ensure backups happen synchronously before database clearing.

## Technical Context

**Language/Version**: Swift (latest stable), Swift Concurrency (`async`/`await`, `@MainActor`)  
**Primary Dependencies**: SwiftData, SwiftUI, Foundation (FileManager), OSLog  
**Storage**: SwiftData (`ModelContainer` with SQLite backing store), file-level SQLite snapshots for backups  
**Testing**: Swift Testing framework (`@Suite`, `@Test`, `#expect`, `#require`)  
**Target Platform**: iOS 17+, iPadOS 17+, macOS 14+ (via Mac Catalyst)  
**Project Type**: Mobile app (feature addition)  
**Performance Goals**: Backup/restore completes within 5 seconds for databases with up to 10,000 entities; non-blocking UI  
**Constraints**: Must not block main thread; single backup per node (1:1 mapping); local storage only  
**Scale/Scope**: 2–5 nodes per user typically; single SQLite file ~5–50MB per backup

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ PASS | Backup management UI will be pure SwiftUI in `Views/Settings/` |
| II. SwiftData Persistence | ✅ PASS | Backup operates at file level below SwiftData; restore replaces the store file and recreates `ModelContainer`. No custom persistence outside SwiftData for app data. |
| III. Protocol-Oriented Transport | ✅ PASS | Backup hooks into `AccessoryManager` connection lifecycle; no direct BLE/network calls |
| IV. Structured Logging | ✅ PASS | Will use `Logger` with new `.backup` category |
| V. Protobuf Contract Fidelity | ✅ PASS | No protobuf changes needed |
| VI. Lint-Clean Commits | ✅ PASS | All code will pass SwiftLint |
| VII. Platform Parity | ✅ PASS | FileManager APIs work cross-platform; UI uses SF Symbols |
| VIII. Design Standards | ✅ PASS | Management UI will follow Meshtastic design standards |

**Gate Result**: PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/011-database-backup-system/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── backup-service-api.md
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
Meshtastic/
├── Model/                               # No new SwiftData models — backup metadata uses JSON index file
├── Persistence/
│   └── NodeBackupManager.swift          # Core backup/restore service
├── Extensions/
│   └── Logger+Backup.swift              # Logger category for backup subsystem
├── Views/
│   └── Settings/
│       └── BackupManagement/
│           ├── BackupManagementView.swift   # List of backups
│           └── BackupRowView.swift          # Individual backup row
├── Views/
│   └── Connect/
│       └── Connect.swift                   # Modified: hook backup before clear (existing file)

MeshtasticTests/
└── NodeBackupManagerTests.swift         # Unit tests for backup service
```

**Structure Decision**: Mobile app feature addition following existing conventions. New files integrate into the established folder structure (`Persistence/` for service logic, `Model/` for entities, `Views/Settings/` for management UI). The backup service is a standalone manager class injected into the connection lifecycle.

## Complexity Tracking

> No constitution violations — this section is intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
