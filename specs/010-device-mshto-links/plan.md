# Implementation Plan: Device msh.to Links

**Branch**: `010-device-mshto-links` | **Date**: 2026-05-15 | **Spec**: `specs/010-device-mshto-links/spec.md`
**Input**: Feature specification from `/specs/010-device-mshto-links/spec.md`

## Summary

Display msh.to links for Meshtastic devices by exact-matching a device's `platformioTarget` against short codes from the bundled `urls.json`. Links open `https://msh.to/{platformioTarget}` which the msh.to redirect service routes to vendor/retailer pages. No new SwiftData entity is needed — short codes are loaded as an in-memory `Set<String>`.

## Technical Context

**Language/Version**: Swift (latest stable)  
**Primary Dependencies**: SwiftUI, SwiftData (existing models only), OSLog, SF Symbols  
**Storage**: No new persistence — short codes loaded from bundled JSON into a static `Set<String>`  
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`)  
**Target Platform**: iOS 17+, iPadOS 17+, macOS (Catalyst)  
**Project Type**: Mobile app (existing)  
**Performance Goals**: Short code set loaded once at first access; link display is instantaneous  
**Constraints**: Bundled-only data source; offline-capable; no new external dependencies; no new SwiftData entities  
**Scale/Scope**: ~200 short codes from urls.json; ~100 device hardware entries; ~49 exact matches

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ PASS | New views use SwiftUI; placed in existing view hierarchy |
| II. SwiftData Persistence | ✅ N/A | No new entities — uses existing `DeviceHardwareEntity.platformioTarget` |
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
├── Views/
│   ├── Nodes/
│   │   └── Helpers/DeviceLinksSection.swift    # Links section in node info + msh.to JSON models
│   └── Settings/
│       └── DeviceLinkDirectory.swift           # Browsable directory (P3)
├── Resources/
│   └── urls.json                               # Bundled msh.to short codes
MeshtasticTests/
└── DeviceLinkTests.swift                       # Unit tests
```

**Structure Decision**: No new model files. Two new view files + bundled JSON. Short code lookup is a static property on `DeviceLinksSection`.

## Complexity Tracking

No violations — significantly simpler than original plan due to exact match on `platformioTarget`.
