# Tasks: Offline Terrain Layer

**Input**: Design documents from `/specs/018-offline-terrain-layer/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Included — the spec's success criteria depend on decode and generation correctness that only unit tests pin down.

**Organization**: Tasks are grouped by user story; US1 → US2 → US3 is the delivery order, each independently shippable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 = terrain download, US2 = hillshade, US3 = contours

---

## Phase 1: Setup (Shared Infrastructure)

- [ ] T001 Create `Meshtastic/Helpers/Map/TerrariumDecoder.swift` — WebP tile → `ElevationTile` grid (`(R×256 + G + B/256) − 32768`), with neighbor-margin stitching support
- [ ] T002 [P] Create `Meshtastic/Helpers/Map/TerrainStore.swift` — actor opening a region's terrain archives via `PMTilesArchive`, serving margin-stitched `ElevationTile`s with an in-memory decode cache
- [ ] T003 [P] `MeshtasticTests/TerrariumDecoderTests.swift` — known Terrarium pixel → elevation round-trips, margin stitching, malformed tile handling

## Phase 2: US1 — terrain downloads with a region (P1)

- [ ] T101 Extend `PMTilesExtractor` to run a terrain extract (global archive; regional archive when the bbox intersects published coverage) for the same bbox as the basemap, with independent retry
- [ ] T102 Extend `OfflineMapRegion` metadata per data-model.md (`terrain` component: archives, byteCount, maxZoom, downloadedAt) and region-directory layout
- [ ] T103 Offline Maps UI: show the terrain component size per region; add an "Add terrain" action for pre-feature regions; failure of the terrain extract leaves the basemap usable and retryable
- [ ] T104 Record archive ETag/Last-Modified at download (contract change-detection)
- [ ] T105 [P] `MeshtasticTests/TerrainStoreTests.swift` — region open, global-only fallback, delete reclaims caches
- [ ] T106 Verify quickstart US1 flow on the simulator with a small mountain bbox

## Phase 3: US2 — hillshade (P2)

- [ ] T201 Create `Meshtastic/Helpers/Map/HillshadeTileOverlay.swift` — `MKTileOverlay` subclass: Horn 3×3 shading (azimuth 315°, altitude 45°) from `TerrainStore`, disk cache per appearance under `hillshade-cache/`, generation off the main actor
- [ ] T202 Wire the overlay into `MeshMapMK`/`ClusterMapView` above basemap fill, below labels/annotations; suppress on hybrid/satellite map types
- [ ] T203 Map settings: Terrain section with Hillshade toggle (`map.terrain.hillshade`, default off); dark-appearance blend curve
- [ ] T204 Attribution: add Mapterhorn to the map attribution surface when terrain renders
- [ ] T205 Verify quickstart US2 flow including airplane mode, region boundary, dark mode, and frame-rate check

## Phase 4: US3 — contours (P3)

- [ ] T301 Create `Meshtastic/Helpers/Map/ContourGenerator.swift` — marching squares over margin-stitched tiles, `ContourIntervalTable` (zoom → minor/index interval, locale unit), serialized `ContourSet` cache under `contour-cache/`
- [ ] T302 Render `ContourSet`s as `MKMultiPolyline` overlays with index-contour emphasis and elevation labels; imagery-legible color on hybrid/satellite
- [ ] T303 Map settings: Contours toggle (`map.terrain.contours`, default off)
- [ ] T304 [P] `MeshtasticTests/ContourGeneratorTests.swift` — synthetic DEMs (cone, saddle, flat sea level), edge continuity across tiles, interval selection, cache invalidation on re-download
- [ ] T305 Verify quickstart US3 flow: intervals refine with zoom, hybrid shows contours only, global-only areas degrade gracefully

## Phase 5: Polish

- [ ] T401 Cache invalidation when `terrain.downloadedAt` changes (re-download); size accounting includes generated caches
- [ ] T402 Docs: update `docs/user/map.md` (terrain download, toggles, attribution) and regenerate bundled docs
- [ ] T403 Confirm LICENSE terms in github.com/mapterhorn/mapterhorn and finalize attribution copy (research.md open item)
- [ ] T404 Profile generation cost on device (hillshade < 50 ms/tile target); tune decode cache size
