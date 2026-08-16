# Data Contract: Mapterhorn Elevation Tiles

**Feature**: 018-offline-terrain-layer
**Date**: 2026-08-16

The app consumes Mapterhorn as published data; there is no API key or negotiated interface. This contract records the shapes the implementation depends on, so upstream changes are detectable.

## Endpoints

| Purpose | URL |
|---|---|
| Global archive (z0–z12) | `https://download.mapterhorn.com/planet.pmtiles` |
| Regional archives (z13–z17) | `https://download.mapterhorn.com/{z}-{x}-{y}.pmtiles` (existence per their coverage page) |
| Single-tile fallback | `https://tiles.mapterhorn.com/{z}/{x}/{y}.webp` |
| TileJSON | `https://tiles.mapterhorn.com/tilejson.json` |

Archives support HTTP range requests (Cloudflare R2), which is what `PMTilesExtractor` requires. The regional archive naming is a z6 tile id.

## Tile format

- Container: PMTiles v3 (same as the Protomaps basemap; existing `PMTilesArchive` reader applies)
- Tile payload: WebP image, 512 × 512 px
- Encoding: Terrarium terrain-RGB — `elevation_m = (R × 256 + G + B ÷ 256) − 32768`
- Decoded on iOS with ImageIO (`CGImageSource`); WebP is natively supported on iOS 14+

## Assumptions the implementation must not silently violate

1. Elevation is meters; no vertical datum conversion is applied.
2. A missing regional archive for a bbox is normal (coverage gaps) — fall back to global data, never fail the download.
3. Tiles are north-up Web Mercator, matching the basemap tiling — no reprojection.
4. Attribution: Mapterhorn credit required when terrain displays; upstream DEM credits via their attribution page. Verify LICENSE at github.com/mapterhorn/mapterhorn during implementation.

## Change detection

The extractor should record the archive `Last-Modified`/`ETag` at download time (the global archive showed `Last-Modified: 2026-05-11` during research). A future re-download of the same region compares these to decide whether terrain needs refreshing.
