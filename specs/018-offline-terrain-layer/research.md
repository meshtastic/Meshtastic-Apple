# Research: Offline Terrain Layer

**Feature**: 018-offline-terrain-layer
**Date**: 2026-08-16
**Status**: Complete

## Research Questions & Findings

### R1: Where does the elevation data come from, and does it fit our download flow?

**Question**: Is there an open elevation source distributed in a form our existing PMTiles bbox-extraction flow can consume?

**Decision**: Mapterhorn (https://mapterhorn.com).

**Rationale**: Mapterhorn distributes Terrarium-encoded terrain-RGB tiles (512 px WebP) bundled into PMTiles archives on Cloudflare R2 — the identical distribution model to the Protomaps basemap the app already extracts by bbox with range requests. Verified from their Data Access page:

- z/x/y endpoint: `https://tiles.mapterhorn.com/{z}/{x}/{y}.webp` (TileJSON at `/tilejson.json`)
- Global archive: `https://download.mapterhorn.com/planet.pmtiles` (z0–z12; ~706 GB total, bbox extracts are small)
- Regional z13–z17 archives named by tile id (e.g. `6-33-22.pmtiles`); a coverage page maps which exist
- Their own documented extract flow is `pmtiles extract --bbox=…` — exactly what `PMTilesExtractor` implements in-app

Coverage: global 30 m, with much finer regional data (USA country-wide 10 m and partial 1 m; most of Europe at 0.25–5 m; Japan, Australia, NZ, Canada partials). Project is open source (github.com/mapterhorn/mapterhorn), NLnet/NGI sponsored, with Protomaps' author involved — the ecosystem alignment is deliberate.

**Alternatives considered**: AWS Terrain Tiles (Tilezen Joerd) — Mapterhorn exists specifically as its maintained successor and publishes a migration guide; no PMTiles distribution. USGS 3DEP direct — US-only and GeoTIFF-based, wrong shape for tile rendering.

### R2: How are elevation values decoded?

**Decision**: Terrarium encoding: `elevation_m = (R × 256 + G + B ÷ 256) − 32768`, decoded from 512 px WebP tiles.

**Rationale**: Documented Mapterhorn format. iOS decodes WebP natively via ImageIO since iOS 14, so no third-party codec is needed — `CGImageSource` → raw RGBA buffer → elevation grid.

### R3: Contours — precompute at download, or generate lazily?

**Decision**: Generate lazily per visible tile with a disk cache, keyed by tile coordinate and interval set.

**Rationale**: This is the approach maplibre-contour proved in production (their contour example is exactly this, client-side). Lazy generation keeps the download small and lets the interval set adapt to zoom instead of baking one interval at download time. Contour continuity across tile edges is handled the same way maplibre-contour does it: decode with a margin of neighbor-tile pixels so isolines meet at boundaries. Marching squares over a 512×512 grid is well within budget off the main actor, and results cache to disk so each tile+interval generates once.

**Alternatives considered**: Precomputing contour geometry for the whole region at download time — simpler at render, but multiplies download-time CPU, fixes intervals forever, and bloats the region for areas never viewed.

### R4: Hillshade algorithm and presentation

**Decision**: Horn's method (standard 3×3 kernel) with fixed azimuth 315°/altitude 45°, rendered to grayscale-with-alpha tiles served by a custom `MKTileOverlay` subclass; drawn above the basemap fill at low alpha, below labels and annotations; a separate blend curve for dark appearance.

**Rationale**: Horn shading is the de-facto standard (GDAL's default). Serving locally computed tiles through `MKTileOverlay` keeps MapKit's tile scheduling, caching, and reuse for free, and needs no changes to how the vector basemap renders. Layering above the basemap at low alpha avoids requiring transparency in the basemap fills.

**Alternatives considered**: Pre-rendered hillshade into the basemap style (no runtime toggle, double storage); multidirectional shading (nicer, more CPU — possible later refinement without API change).

### R5: Map-type behavior

**Decision**: Hillshade renders on standard and the offline vector basemap only. Contours render on all map types; on hybrid/satellite they use an imagery-legible color and are the sole terrain treatment.

**Rationale**: Satellite imagery already conveys relief; alpha-blended shading over imagery reads as murk. Contours over imagery are a classic, useful combination. Decided with the maintainer.

### R6: Storage and lifecycle

**Decision**: Terrain artifacts live inside the existing per-region directory managed by `OfflineMapManager`: the extract archives (`terrain-global.pmtiles`, optional `terrain-regional.pmtiles`) plus `hillshade-cache/` and `contour-cache/` subdirectories. Deleting the region deletes everything; region size reporting sums all components.

**Rationale**: Matches the established region layout and makes FR-008/FR-009 (cache scoping, size accounting) fall out of directory structure rather than bookkeeping.

### R7: Attribution and license

**Decision**: When terrain is enabled, the map attribution surface adds Mapterhorn, linking to their attribution page (which carries upstream DEM credits: USGS 3DEP, swisstopo, national agencies).

**Open item for implementation**: verify the exact license text in github.com/mapterhorn/mapterhorn LICENSE before ship; the site fetch for the attribution page was inconclusive during research.
