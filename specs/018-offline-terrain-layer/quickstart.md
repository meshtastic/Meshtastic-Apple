# Quickstart: Offline Terrain Layer

**Feature**: 018-offline-terrain-layer

How to verify the feature end to end once implemented. Pick a mountainous bbox with regional coverage (the Mapterhorn docs use Interlaken, `7.74,46.60,7.96,46.75`; any US mountain town works — USA has country-wide 10 m).

## US1 — terrain downloads with a region

1. Map tab → map settings → Offline Maps → download a new region over mountains.
2. Confirm the download UI shows a terrain component and its size.
3. After completion, the region row lists basemap and terrain sizes separately.
4. Files exist under the region directory: `terrain-global.pmtiles` (always) and `terrain-regional.pmtiles` (when the coverage page lists the area).
5. Delete the region → the whole directory including caches is gone.
6. Regression: a region downloaded before this feature shows an "Add terrain" action instead of forcing a re-download.

## US2 — hillshade

1. Enable Settings → map settings → Terrain → Hillshade.
2. Airplane mode on; map type standard or the offline basemap: shaded relief renders under labels and node markers.
3. Pan beyond the region: hillshade ends at the boundary, no errors, no network.
4. Switch to hybrid or satellite: hillshade disappears (toggle state unchanged).
5. Dark mode: shading blends with the dark basemap rather than graying it out.
6. Performance: pan/zoom over cached areas at normal frame rate; first view of a new area generates without hitching the basemap (watch for main-thread stalls with the app hang telemetry).

## US3 — contours

1. Enable Terrain → Contours (airplane mode still on).
2. Contour lines render with emphasized, labeled index contours; labels use feet or meters per locale.
3. Zoom in: intervals refine; lines stay continuous across tile boundaries (no combing at tile edges).
4. Hybrid/satellite: contours remain — the only terrain treatment — in an imagery-legible color.
5. Global-only coverage area (no regional archive): contours still render at intervals the 30 m data supports.

## Attribution

With either toggle on, the map attribution includes Mapterhorn.

## Unit tests

```bash
xcodebuild test -project Meshtastic.xcodeproj -scheme Meshtastic \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MeshtasticTests/TerrariumDecoderTests \
  -only-testing:MeshtasticTests/ContourGeneratorTests \
  -only-testing:MeshtasticTests/TerrainStoreTests
```

Verify executed test counts — decode round-trips known Terrarium pixel values, contour generation against synthetic DEMs (cone, saddle, flat), interval-table selection, and cache invalidation on re-download.
