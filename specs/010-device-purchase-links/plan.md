# Implementation Plan: Device msh.to Links

**Branch**: `010-device-purchase-links` | **Date**: 2026-05-15 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/010-device-purchase-links/spec.md`

## Summary

Import the meshtastic/msh.to `urls.json` from a bundled file during the existing device hardware refresh cycle. Associate links with device hardware entities using substring matching (shortCode contains hwModelSlug). Display matched links in the node info view ordered by vendor priority and user locale. Non-device links are retained for a future browsable directory (P3).

## Technical Context

**Language/Version**: Swift (latest stable), Swift Concurrency  
**Primary Dependencies**: SwiftUI, SwiftData, MeshtasticAPI (existing)  
**Storage**: SwiftData (`ModelContainer` / `ModelContext`)  
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`)  
**Target Platform**: iOS 17+, iPadOS 17+, macOS (Catalyst)  
**Project Type**: Mobile app (existing codebase extension)  
**Performance Goals**: Link import completes in <100ms (local JSON decode, no network)  
**Constraints**: Offline-capable (bundled file only in v1), no new network requests  
**Scale/Scope**: ~140 link entries, ~70 device hardware entities

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ Pass | Links section uses SwiftUI List/Section in existing NodeInfoItem view |
| II. SwiftData Persistence | ✅ Pass | New `DeviceHardwareLinkEntity` @Model type, schema migration |
| III. Protocol-Oriented Transport | ✅ N/A | No transport layer changes |
| IV. Structured Logging | ✅ Pass | Will use `Logger.services` for import logging |
| V. Protobuf Contract Fidelity | ✅ N/A | No protobuf changes |
| VI. Lint-Clean Commits | ✅ Pass | CodingKeys for PascalCase JSON fields |
| VII. Platform Parity | ✅ Pass | SwiftUI + SwiftData works on all targets |
| VIII. Design Standards | ✅ Pass | Standard List rows with SF Symbols |

No violations. No complexity justification needed.

## Project Structure

### Documentation (this feature)

```text
specs/010-device-purchase-links/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (N/A — no external interfaces)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
Meshtastic/
├── Model/
│   └── DeviceHardwareLinkEntity.swift         # NEW — @Model for msh.to link entries
├── Model/Schema/
│   └── MeshtasticSchemaV1.swift               # MODIFIED — register new entity
├── API/
│   └── MeshtasticAPI.swift                    # MODIFIED — add refreshDeviceLinks()
├── Resources/
│   └── DeviceLinks.json                       # NEW — bundled copy of msh.to urls.json
├── Views/Nodes/Helpers/
│   └── NodeInfoItem.swift                     # MODIFIED — add Links section
└── Extensions/
    └── DeviceHardwareLinkEntity+Priority.swift # NEW — vendor priority + locale sorting

MeshtasticTests/
└── DeviceLinksTests.swift                     # NEW — tests for import + matching logic

scripts/
└── update-device-links.sh                    # NEW — CI script to refresh bundled JSON
```

**Structure Decision**: Follows existing pattern — model in `Model/`, API logic in `API/`, UI in `Views/Nodes/Helpers/`, tests in `MeshtasticTests/`.
