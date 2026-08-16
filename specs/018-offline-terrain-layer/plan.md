# Implementation Plan: Offline Terrain Layer

**Branch**: `018-offline-terrain-layer` | **Date**: 2026-08-16 | **Spec**: `specs/018-offline-terrain-layer/spec.md`
**Input**: Feature specification from `/specs/018-offline-terrain-layer/spec.md`

## Summary

Add hillshade and contour lines to offline map regions using Mapterhorn elevation data. The offline download gains a second bbox extract (Terrarium terrain-RGB tiles in PMTiles form, same range-request flow the basemap already uses). Rendering stays MapKit: hillshade is computed on device from the elevation tiles and served through a custom `MKTileOverlay`; contours are generated on device with marching squares and rendered as `MKMultiPolyline` overlays. Standard and the offline vector basemap show both; hybrid and satellite show contours only. Two phases: (1) terrain download + hillshade, which builds all shared plumbing (extraction, Terrarium decode, caches); (2) contours.

## Technical Context

**Language/Version**: Swift (latest stable), Swift Concurrency (`async`/`await`, actors for generation work)
**Primary Dependencies**: MapKit (`MKTileOverlay`, `MKMultiPolyline`), Foundation, ImageIO/CoreGraphics (WebP decode), existing PMTiles machinery (`PMTilesArchive`, `PMTilesExtractor`), OSLog
**Storage**: Per-region `.pmtiles` terrain extracts plus file-based hillshade/contour caches under the existing `OfflineMapManager` region directory; no SwiftData schema changes
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`) — Terrarium decode, contour generation (synthetic DEMs), interval selection, cache invalidation
**Target Platform**: iOS 17+, iPadOS 17+, macOS 14+ (Catalyst); tvOS follow-on possible (shares the map files)
**Project Type**: Mobile app (feature addition to the offline maps system)
**Performance Goals**: Map pan/zoom at normal frame rate over cached terrain; first-view tile generation off the main thread with no basemap hitching; hillshade tile generation target < 50 ms/tile on device
**Constraints**: Fully offline after download; no MapLibre; no 3D terrain; region delete reclaims all storage; generation must never block the main actor
**Scale/Scope**: Typical region bbox (city to county scale), z0–12 global data plus z13–17 regional coverage where available; two new overlay types in the existing map pipeline

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ PASS | Settings toggles are SwiftUI; map rendering already lives in the MKMapView representable |
| II. SwiftData Persistence | ✅ PASS | No app-data model changes; terrain artifacts are files scoped to offline regions, same pattern as the basemap extract |
| III. Protocol-Oriented Transport | ✅ PASS | No transport changes; downloads reuse the existing extractor's URLSession flow |
| IV. Structured Logging | ✅ PASS | `Logger` map/services categories for extract, decode, and generation |
| V. Protobuf Contract Fidelity | ✅ PASS | No protobuf involvement |
| VI. Lint-Clean Commits | ✅ PASS | SwiftLint applies as usual |
| VII. Platform Parity | ✅ PASS | Catalyst works with the same MapKit code; tvOS can adopt later since map files are shared |
| VIII. Design Standards | ✅ PASS | Toggles follow MapSettingsForm conventions; attribution surfaced per design |

**Gate Result**: PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/018-offline-terrain-layer/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── mapterhorn-data-contract.md
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
Meshtastic/
├── Helpers/Map/
│   ├── PMTilesExtractor.swift            # extended: terrain extract alongside basemap
│   ├── TerrainStore.swift                # NEW: per-region terrain archives + decode access
│   ├── TerrariumDecoder.swift            # NEW: WebP tile → elevation grid
│   ├── HillshadeTileOverlay.swift        # NEW: MKTileOverlay computing shaded relief locally
│   ├── ContourGenerator.swift            # NEW: marching squares + interval selection + caching
│   └── OfflineMapRegion.swift            # extended: terrain component + sizes
├── Views/Nodes/
│   └── MeshMapMK.swift / ClusterMapView  # extended: overlay wiring + map-type gating
└── Views/Settings/
    └── MapSettingsForm                   # extended: Terrain section (Hillshade / Contours toggles)

MeshtasticTests/
├── TerrariumDecoderTests.swift           # NEW
├── ContourGeneratorTests.swift           # NEW
└── TerrainStoreTests.swift               # NEW
```

## Phase Outline

**Phase 0 (research)**: complete — see `research.md` (Mapterhorn distribution model, decode formula, WebP support, hillshade algorithm, contour approach, layering).

**Phase 1 (design)**: complete — see `data-model.md`, `contracts/mapterhorn-data-contract.md`, `quickstart.md`.

**Phase 2 (tasks)**: see `tasks.md`. Delivery order is US1 (terrain download) → US2 (hillshade) → US3 (contours); each user story is independently shippable.
