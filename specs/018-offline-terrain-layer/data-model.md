# Data Model: Offline Terrain Layer

**Feature**: 018-offline-terrain-layer
**Date**: 2026-08-16

No SwiftData schema changes. All terrain state is file-based and scoped to the existing offline-region storage, extending the JSON metadata `OfflineMapManager` already keeps per region.

## Region metadata (extended)

`OfflineMapRegion` (existing JSON-backed record) gains a terrain component:

| Field | Type | Notes |
|---|---|---|
| `terrain` | optional object | Absent for regions without terrain (pre-feature downloads) |
| `terrain.globalArchive` | string (filename) | `terrain-global.pmtiles`, extract of the z0–12 planet archive |
| `terrain.regionalArchive` | optional string | Extract of the intersecting z13+ archive when coverage exists |
| `terrain.downloadedAt` | date | Drives cache invalidation |
| `terrain.byteCount` | integer | Sum of archive sizes, shown in Offline Maps |
| `terrain.maxZoom` | integer | 12 when global-only, per regional archive otherwise |

## On-disk layout (per region directory)

```text
<region>/
├── basemap.pmtiles                # existing
├── terrain-global.pmtiles         # NEW (US1)
├── terrain-regional.pmtiles       # NEW, optional (US1)
├── hillshade-cache/               # NEW (US2) — {appearance}/{z}/{x}/{y}.png
└── contour-cache/                 # NEW (US3) — {intervalSet}/{z}/{x}/{y}.geometry
```

Deleting the region directory removes every terrain artifact (FR-008). Cache directories are recreated on demand; both are invalidated whenever `terrain.downloadedAt` changes.

## In-memory types (new, value types unless noted)

- **`ElevationTile`**: decoded Terrarium grid — `zxy`, `Float` elevations (512×512 plus neighbor margin), `resolutionMeters`. Produced by `TerrariumDecoder`, consumed by hillshade and contour generation.
- **`TerrainStore`** (actor): opens the region's archives, serves `ElevationTile`s with the neighbor margin stitched in, owns decode caching.
- **`HillshadeTileOverlay`** (`MKTileOverlay` subclass): resolves tiles from `hillshade-cache/`, generating misses via `TerrainStore` off the main actor; keyed by appearance (light/dark).
- **`ContourSet`**: generated polylines for one tile — interval metadata, index-contour flags, label anchor points; serialized into `contour-cache/`.
- **`ContourIntervalTable`**: zoom → (minor, index) interval mapping, unit-aware (m/ft by locale).

## Settings

`@AppStorage` keys following existing map settings conventions:

| Key | Type | Default |
|---|---|---|
| `map.terrain.hillshade` | Bool | false |
| `map.terrain.contours` | Bool | false |

Map-type gating (hillshade suppressed on hybrid/satellite) is derived at render time from the existing map-type setting, not stored.
