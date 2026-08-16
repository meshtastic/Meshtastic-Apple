# Feature Specification: Offline Terrain Layer

**Feature Branch**: `018-offline-terrain-layer`
**Created**: 2026-08-16
**Status**: Draft — approved direction, not yet implemented
**Input**: User description: "Use Mapterhorn to get contour lines for our Protomaps offline downloads. I want hillshade and contours (Option D) on MapKit — not switching to MapLibre. On hybrid, contours only."

## Overview

The app already downloads an offline vector basemap by extracting a bounding box from the public Protomaps planet build into a local `.pmtiles` file. [Mapterhorn](https://mapterhorn.com) distributes global elevation data the same way — Terrarium-encoded terrain-RGB tiles (512px WebP) in PMTiles archives that support bbox range extraction — so an offline region can gain a terrain layer with one more extract of the same bounding box.

Nothing about the map framework changes: rendering stays MapKit. Hillshade renders as a locally computed raster tile overlay; contours render as vector polylines through the same overlay pipeline the basemap uses. True 3D terrain is explicitly out of scope — that is a MapLibre feature and the map is not moving to MapLibre.

Delivery is two phases sharing one foundation: Phase 1 is the terrain download plus hillshade (all shared plumbing: extraction, Terrarium decode, tile cache). Phase 2 is contour generation and rendering. A follow-on (not this spec) can reuse the on-device elevation data for site-planner line-of-sight and route elevation profiles.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Download terrain with an offline region (Priority: P1)

When a user downloads (or re-downloads) an offline map region, the download includes elevation data for the same bounding box. The Offline Maps UI shows the terrain portion's size and completes both extracts as one operation.

**Why this priority**: Nothing renders without the data on device; this is the foundation both phases sit on.

**Independent Test**: Download a region with terrain enabled, put the device in airplane mode, and verify the terrain files exist in the region's storage and are listed with sizes in Offline Maps.

**Acceptance Scenarios**:

1. **Given** the offline region download form, **When** the user starts a download, **Then** the elevation extract for the same bbox is fetched alongside the basemap extract (global archive; plus the finer regional archive when the bbox has coverage) and stored with the region.
2. **Given** a completed download, **When** the user views Offline Maps, **Then** the region lists the terrain data and its size separately from the basemap.
3. **Given** a region is deleted, **Then** its terrain files and any generated hillshade/contour caches are removed with it.
4. **Given** the terrain extract fails partway, **Then** the basemap remains usable, the failure is reported, and terrain can be retried without re-downloading the basemap.

---

### User Story 2 - Hillshade on the map (Priority: P2)

With terrain downloaded, the standard map and the offline vector basemap show shaded relief beneath the map content. A Terrain setting in the map settings turns it on and off.

**Why this priority**: Largest visual payoff for the smallest rendering surface; forces the decode and cache layers into existence for Phase 2.

**Independent Test**: With a downloaded mountainous region and airplane mode on, enable hillshade and verify shaded relief renders on the offline basemap; toggle off and verify it disappears without disturbing the basemap.

**Acceptance Scenarios**:

1. **Given** terrain data for the visible area and hillshade enabled, **When** the map renders in standard or offline-basemap mode, **Then** shaded relief appears under labels and node annotations.
2. **Given** hybrid or satellite map type is selected, **Then** hillshade does not render regardless of the toggle — imagery already conveys relief and blended shading muddies it.
3. **Given** dark mode, **Then** the hillshade uses a dark-appearance blend (no washed-out gray film over the dark basemap).
4. **Given** the map pans outside the downloaded region, **Then** hillshade simply ends at the region boundary; no errors and no network fetches.

---

### User Story 3 - Contour lines (Priority: P3)

With terrain downloaded, the map can show elevation contour lines with labeled intervals appropriate to the zoom level. Contours render on every map type — on hybrid and satellite they are the only terrain treatment, drawn in a color legible over imagery.

**Why this priority**: The full topo look and the headline user request, built on the Phase 1 foundation.

**Independent Test**: Enable contours over a downloaded region, verify lines with elevation labels at sensible intervals, zoom in and verify intervals refine, switch to hybrid and verify contours (and only contours) remain.

**Acceptance Scenarios**:

1. **Given** contours enabled and terrain data present, **When** the map renders, **Then** contour lines appear with index contours emphasized and labeled in the user's elevation unit (feet/meters following locale).
2. **Given** the map type is hybrid or satellite, **Then** contours render in an imagery-legible color and hillshade stays off.
3. **Given** the user zooms, **Then** the contour interval adapts (coarser out, finer in) without seams at tile boundaries.
4. **Given** terrain is downloaded but only at global 30 m resolution (no regional high-res coverage), **Then** contours still render, limited to intervals the data supports.

---

### Edge Cases

- Bbox has no regional z13+ archive coverage: fall back to the global 30 m data alone; never fail the download for missing high-res.
- Existing offline regions downloaded before this feature: offer terrain as an add-on download rather than forcing a full re-download.
- Contour generation is CPU work: generate off the main thread, cache results per tile+interval, and invalidate caches when the region's terrain files change.
- Tile-edge continuity: contour generation must read neighbor-pixel margins so lines join across tile boundaries.
- Storage pressure: terrain extract size is shown before download; generated caches count toward the region's displayed size.
- Attribution: Mapterhorn aggregates national DEMs (USGS 3DEP, swisstopo, and others); the map attribution surface must include it when terrain is enabled.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Offline region downloads MUST optionally include a terrain extract of the same bounding box from the Mapterhorn PMTiles archives (global z0–12 archive, plus the intersecting regional z13+ archive when available), stored with the region.
- **FR-002**: The app MUST decode Terrarium terrain-RGB tiles to elevation grids on device (`elevation = R×256 + G + B/256 − 32768`).
- **FR-003**: Hillshade MUST render as a locally computed raster tile overlay on the standard map and the offline vector basemap only, beneath labels and annotations, with light/dark-appearance handling. No network access at render time.
- **FR-004**: Contours MUST render as vector polylines on all map types; on hybrid and satellite they render without hillshade and in a color chosen for legibility over imagery.
- **FR-005**: Contour intervals MUST adapt to zoom, with emphasized and labeled index contours; labels follow the user's locale elevation unit.
- **FR-006**: Map settings MUST gain independent Hillshade and Contours toggles, defaulting to off. Both toggles are disabled until at least one region has terrain data downloaded.
- **FR-007**: All terrain rendering MUST work fully offline once the extract is downloaded.
- **FR-008**: Generated hillshade tiles and contour geometry MUST be cached on disk, scoped to the region, and deleted with it.
- **FR-009**: The Offline Maps UI MUST show the terrain component's size per region and support adding terrain to a previously downloaded region.
- **FR-010**: The attribution surface MUST credit Mapterhorn (and its upstream sources page) whenever terrain data is displayed.

### Key Entities

- **Terrain extract**: the per-region elevation `.pmtiles` file(s) — one from the global archive, optionally one regional high-res.
- **Hillshade cache**: locally rendered raster tiles keyed by tile coordinate and appearance.
- **Contour cache**: generated polylines keyed by tile coordinate and interval set.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can download a region and see hillshade and labeled contours on the offline basemap in airplane mode.
- **SC-002**: Map pan/zoom over cached terrain sustains the map's normal frame rate; first-view generation happens off the main thread with no visible hitching of the basemap.
- **SC-003**: Hybrid and satellite show contours only; standard and offline basemap can show both.
- **SC-004**: Deleting a region reclaims all terrain and cache storage.

## Assumptions

- Mapterhorn's endpoints (`download.mapterhorn.com` archives, coverage listing) remain publicly available; the extract flow reuses the existing PMTilesExtractor range-request machinery.
- Mapterhorn's license permits app use with attribution (open source project; attribution page lists upstream DEM requirements — verify exact license text during implementation).
- Contour generation ports the marching-squares approach used by maplibre-contour (client-side generation from elevation tiles); no server-side contour data exists or is wanted.
- 3D terrain is permanently out of scope for this feature; the map remains MKMapView.
- tvOS terrain is an explicit follow-on: the TV app already reads the shared offline map files, so it can adopt the terrain layer once the iOS implementation lands.

## iOS Implementation Reference

- Extraction/storage: `Meshtastic/Helpers/Map/PMTilesExtractor.swift`, `OfflineMapRegion`/`OfflineMapManager` — the terrain extract is a second archive per region.
- Rendering: `MeshMapMK`/`ClusterMapView` overlay pipeline; hillshade as a custom `MKTileOverlay` subclass rendering from the local extract; contours as `MKMultiPolyline` overlays.
- Follow-on (separate spec): on-device elevation queries for site-planner line-of-sight and traceroute elevation profiles reuse the FR-002 decode layer.
