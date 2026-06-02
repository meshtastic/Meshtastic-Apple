# Implementation Plan: Device msh.to Links

**Branch**: `010-device-mshto-links` | **Date**: 2026-05-15 | **Spec**: `specs/010-device-mshto-links/spec.md`
**Input**: Feature specification from `/specs/010-device-mshto-links/spec.md`

## Summary

Display msh.to links for Meshtastic devices using multi-tier matching of a device's `platformioTarget` against short codes from the bundled `urls.json`. A separate bundled `marketplaces.json` defines marketplace identifiers and shipping regions. Links open `https://msh.to/{shortCode}` which the msh.to redirect service routes to the correct vendor/retailer page.

> **Note — plan was revised during implementation**: The original plan below assumed no new SwiftData entity was needed (exact-match only, in-memory Set). The final implementation adds `DeviceLinkEntity` (SwiftData) and `marketplaces.json` to support multi-tier matching, marketplace region filtering, vendor/marketplace categorisation, and upsert/orphan cleanup. See `data-model.md` for the accurate as-built data model.

## Technical Context

**Language/Version**: Swift (latest stable)  
**Primary Dependencies**: SwiftUI, SwiftData (existing models only), OSLog, SF Symbols  
**Storage**: `DeviceLinkEntity` (SwiftData, upserted per short code from bundled JSON)  
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`)  
**Target Platform**: iOS 17+, iPadOS 17+, macOS (Catalyst)  
**Project Type**: Mobile app (existing)  
**Performance Goals**: Short code set loaded once at first access; link display is instantaneous  
**Constraints**: Bundled-only data source for v1; offline-capable; no new external dependencies
**Scale/Scope**: ~200 short codes from urls.json; ~100 device hardware entries

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ PASS | New views use SwiftUI; placed in existing view hierarchy |
| II. SwiftData Persistence | ✅ PASS | `DeviceLinkEntity` added; upserted from bundled JSON |
| III. Protocol-Oriented Transport | ✅ N/A | No transport changes |
| IV. Structured Logging | ✅ N/A | No logging needed — simple in-memory lookup |
| V. Protobuf Contract Fidelity | ✅ N/A | No proto changes |
| VI. Lint-Clean Commits | ✅ PASS | Will follow SwiftLint rules |
| VII. Platform Parity | ✅ PASS | Links view works on all platforms |
| VIII. Design Standards | ✅ PASS | Will review design standards before UI work |

## Project Structure

### Documentation (this feature)

```text
specs/010-device-mshto-links/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (N/A - no external APIs)
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
Meshtastic/
├── Model/
│   └── DeviceLinkEntity.swift               # SwiftData entity for msh.to link records
├── Views/
│   ├── Nodes/
│   │   └── Helpers/DeviceLinksSection.swift # Links section in node info ("I want one")
│   └── Settings/
│       └── DeviceLinkDirectory.swift        # Browsable directory in Settings (P3)
├── Resources/
│   ├── urls.json                            # Bundled msh.to short codes (from msh.to repo)
│   └── marketplaces.json                   # Marketplace metadata (app-maintained)
MeshtasticTests/
└── DeviceLinkTests.swift                   # Unit tests
```

## Complexity Tracking

Final implementation is more complex than the original exact-match plan:
- SwiftData entity added for persistence, upsert, and orphan cleanup
- `marketplaces.json` added for region-aware marketplace filtering
- Multi-tier matching in `DeviceLinksSection` (vendor > variant > marketplace)
- Refresh lifecycle hardened: catalog repopulated on every connect and after DB clear
- Architecture field must be decoded as `String` (not enum) — see spec.md Implementation Notes
