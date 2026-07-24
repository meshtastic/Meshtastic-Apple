# Diagnosis: Offline map freeze at ~1.5mi zoom, offline only

**Branch:** `diagnose/offline-maps-freeze` (isolated worktree, diagnosis only — no code changes made)

## Bug report

> Tried the offline maps this weekend. Multiple times I would zoom in to the offline
> area we were in and the map view would freeze, force close was the only reset. No
> issues once I had even the slightest of service again. Map froze when the scale
> was in the 1.5mi range.

## Summary of the current offline-map implementation

The repo's offline map feature has been rewritten since the `MKTileOverlay`/raster
approach the old comments and file headers still reference. Stale comments (e.g.
`ClusterMapView.swift:610` — *"retained offline `tileOverlay` (that's owned by
`installTileOverlay`)"*) describe a raster `MKTileOverlay` pipeline that **no longer
exists in this codebase** — there is no `installTileOverlay` function and no
`MKTileOverlay` subclass anywhere in `Meshtastic/` (confirmed by full-text search).

The live pipeline, end to end:

1. **`OfflineMapManager`** (`Meshtastic/Helpers/Map/OfflineMapManager.swift`) owns
   downloaded `.pmtiles` archives under `Documents/OfflineMaps/`, tracked in a JSON
   manifest. Pure local file management, no network at view time.
2. **`PMTilesArchive`** / **`MBTilesArchive`** (`Meshtastic/Helpers/Map/PMTilesArchive.swift`,
   `MBTilesArchive.swift`) are local-only readers — memory-mapped file (`PMTilesArchive`)
   or SQLite (`MBTilesArchive`). **Neither has any network fallback path.** If a tile
   isn't found locally, `tileData(z:x:y:)` returns `nil`, full stop
   (`PMTilesArchive.swift:145-172`, `MBTilesArchive.swift:88-104`). This rules out the
   "cached-tile-miss falls back to a network fetch" hypothesis from the bug report —
   that code path doesn't exist any more.
3. **`OfflineVectorTileProvider`** (`Meshtastic/Views/Nodes/Helpers/Map/PMTilesMapView.swift`)
   opens the downloaded archives, decodes their MVT vector tiles into native
   `MapPolygon`/`MapPolyline`-shaped Swift structs, and stitches road segments into
   long polylines. This is a **local decode of local vector geometry — zero network
   calls anywhere in this file.**
4. **`MeshMapMK.swift`** (the live map screen) feeds the decoded shapes into
   **`ClusterMapView`** (`Meshtastic/Views/Nodes/Helpers/Map/ClusterMapView.swift`),
   a `UIViewRepresentable` around `MKMapView`, which renders them as
   `MKPolygon`/`MKMultiPolygon`/`MKMultiPolyline` overlays **drawn on top of** Apple's
   live basemap (`MKStandardMapConfiguration`/`MKHybridMapConfiguration`/
   `MKImageryMapConfiguration`, all with `elevationStyle: .flat`).

I read every file in this pipeline end to end and grepped the whole map-adjacent
surface for `URLSession`, `CLGeocoder`, `MKLocalSearch`, `DispatchSemaphore`, `.wait()`,
`dataTask`, and `MKTileOverlay`. **There is no network call, semaphore, or blocking
wait anywhere in the code path that runs while a user pans/zooms the map.** The only
geocoding/search calls in the whole map area (`CLGeocoder` in
`CoverageEstimateForm.swift:238`, `DownloadNewMapView.swift:98/107`, `MQTTConfig.swift:377`)
live in the *Site Planner* and *download a new offline map* flows — neither is
reachable from simply viewing/zooming a map you've already downloaded.

That absence is itself important evidence: **since no app code in the viewing path
touches the network, the "fixed instantly by any connectivity" detail can only be
explained by (a) something outside this repo's code — i.e. MapKit/CFNetwork's own
internal behavior — or (b) a main-thread CPU cost in our own code that happens to
line up with when MapKit's internal behavior is also under the most stress.** The
ranked hypotheses below reflect that.

---

## Hypothesis 1 (most likely): live Apple basemap network contention colliding with the offline vector overlay's one-time CPU/overlay-construction burst, both triggered at the same "region first becomes visible" moment

### The zoom/scale correlation is real and in-code

`OfflineVectorTileProvider.updateIfNeeded()` (`PMTilesMapView.swift:145-172`) is a
**lazy, once-per-archive-set decode**, gated by `didLoad`:

```swift
func updateIfNeeded() {
    guard !didLoad, !vectorSources.isEmpty else { return }
    didLoad = true
    ...
    queue.async { [weak self] in
        // decode + stitch up to maxTiles=48 tiles at the deepest zoom that fits
        ...
        Task { @MainActor [weak self] in
            self.polygons = allPolygons
            self.roads = allRoads
            self.revision += 1
        }
    }
}
```

It's only called (`MeshMapMK.swift:1044-1046`, `decodeOfflineIfVisible()`) when
`offlineRegionOnScreen()` (`MeshMapMK.swift:1049-1057`) says the downloaded region's
coverage box actually intersects the (padded) viewport. For a user who starts zoomed
out over the mesh and then zooms in on their own downloaded area, **the first time
that happens is exactly when they reach a local, street-level scale** — the report's
"~1.5mi" is consistent with that.

The tile-zoom this decode picks is *itself* keyed to the residential street grid:

```swift
// PMTilesMapView.swift:98-100
/// `boundsTiles` picks the highest fixed zoom whose tile count fits this cap. Residential
/// streets only exist in Protomaps tiles at z13+, so ~48 lands on z14 (full street grid).
private let maxTiles = 48
```

`z13/z14` is the same zoom band that a ~1.5 mile map scale bar corresponds to. So the
one-time decode is architecturally tied to "just zoomed to street level over the
offline area" — matching the report's specific scale far more precisely than
coincidence would predict.

### What actually runs, and where

- **Decode + road-stitch** (`Self.build`, `PMTilesMapView.swift:196-236` +
  `stitch(_:)` at `PMTilesMapView.swift:281-315`) runs on a background
  `DispatchQueue` (`queue.async`, `PMTilesMapView.swift:95/150`) — not directly on
  the main thread. For a "High detail" (`maxZoom = 15`, `OfflineMapManager.swift:31`)
  archive over a populated area, this is real CPU work: decoding MVT protobufs for
  up to 48 tiles, building per-role segment lists, and doing an O(n)-ish
  endpoint-matching stitch pass over every road segment in the archive
  (`PMTilesMapView.swift:295-315`).
- **Overlay construction is synchronous on the main actor.** Once `revision` bumps,
  `MeshMapMK.swift`'s `overlayInputsKey` changes, firing
  `.onChange(of: overlayInputsKey) { rebuildAllMapContent() }`
  (`MeshMapMK.swift:623-625`) → `rebuildOfflineVectorOverlays()`
  (`MeshMapMK.swift:1395-1478`). This method is **not backgrounded** — it runs on
  the view's (main) actor and builds `MKPolygon`/`MKMultiPolygon`/`MKMultiPolyline`
  objects for every decoded fill and every stitched road, batched per role but still
  potentially hundreds to low-thousands of coordinate-array allocations and MapKit
  shape objects for a dense "High detail" region (`MeshMapMK.swift:1406-1478`).
- Those overlays are then handed to `ClusterMapView.Coordinator.syncOverlays`
  (`ClusterMapView.swift:608-635`), which calls `mapView.addOverlay(...)` for each
  one, and MapKit must allocate a renderer for each via
  `mapView(_:rendererFor:)` (`ClusterMapView.swift:862-895`) and tessellate/draw it.

None of this is network-dependent by itself, and none of it explains "offline only"
in isolation — which is why this is presented as a **collision**, not a standalone
cause.

### The connectivity-dependent half: Apple's own basemap is still live underneath

`ClusterMapView.applyConfiguration` (`ClusterMapView.swift:453-482`) always sets a
real `MKStandardMapConfiguration` / `MKHybridMapConfiguration` /
`MKImageryMapConfiguration` as `mapView.preferredConfiguration` — the offline vector
overlay is explicitly documented as drawing **on top of**, not **instead of**, that
live basemap:

```swift
// ClusterMapView.swift:33-34
/// Declarative basemap config applied to the MKMapView (Apple basemap type + controls). The offline
/// raster `.pmtiles` overlay (when `tilesURL` is set) draws ON TOP of whatever this selects.
```

So even while fully offline and looking at a downloaded region, MapKit is still the
one responsible for the *surrounding*/underlying Apple Maps tiles, and it still
believes it has a configured, live tile source — this app never tells MapKit "there
is no network, don't bother." **There is no `NWPathMonitor`, reachability check, or
any other connectivity awareness anywhere in the map code** (confirmed by grep across
`Meshtastic/` for `NWPathMonitor`/`Reachability`/`Network.framework`import outside of
unrelated BLE/TAK/OTA code). MapKit's tile-fetch layer under **zero** network
reachability (not merely a slow/lossy one) has a long-documented asymmetry with
CFNetwork/Network.framework: a live-but-failing interface usually fails a request
fast (immediate "not connected" style error), while genuinely *no* interface at all
can leave in-flight/queued requests retrying against internal timeouts for many
seconds before giving up, competing for the same dispatch/XPC resources the main run
loop depends on for UI event delivery.

### Why this explains every detail in the report

- **Freezes only offline:** our own code never checks connectivity, so the only way
  "having service" fixes something is if a *live* Apple/CFNetwork operation is what's
  actually blocking. Once there's any signal, MapKit's tile requests resolve (or
  fail) quickly instead of retrying/timing out, and whatever contention exists
  clears.
- **Specifically at ~1.5mi scale:** that's precisely the zoom/tile-level threshold
  the offline decode is written to target (`maxTiles = 48` landing on the "full
  street grid" zoom, `PMTilesMapView.swift:98-100`), and it's also the first moment
  `offlineRegionOnScreen()` goes true for a user who zooms from an overview into
  their downloaded area — the one-time CPU burst (decode + main-actor overlay
  construction + MapKit overlay tessellation) and the live basemap's own network
  activity both spike at the same instant.
- **Full freeze, force-quit required:** a stalled CFNetwork/MapKit operation
  competing with a genuine multi-hundred-millisecond-to-multi-second main-actor CPU
  burst (`rebuildOfflineVectorOverlays`) is exactly the shape of bug that presents as
  "totally unresponsive to touch" rather than a crash or exception a debugger would
  catch — there's nothing to catch, the main thread's run loop is just starved long
  enough that iOS never recovers gracefully and the user has to force-quit.
- **Resolves instantly with any connectivity, recurs "multiple times":**
  `OfflineVectorTileProvider` is held in a `@StateObject`
  (`MeshMapMK.swift:78: @StateObject private var offlineVectors = OfflineVectorTileProvider()`)
  and `didLoad` is a plain instance flag with no persistence — it resets on every
  fresh view/app-process lifetime. So the same "first time the region comes on
  screen at street zoom" trigger fires again after every relaunch (i.e. after every
  forced quit), matching "multiple times... force close was the only reset."

---

## Hypothesis 2 (secondary, in-repo, worth ruling in/out with Instruments): the offline overlay build/decode is heavy enough on its own to look like a freeze, independent of any network contention

Everything described under "What actually runs, and where" above is real,
quantifiable CPU/allocation cost, and it's the *only* mechanism in this codebase
whose cost structurally scales with the zoom-selected tile count and with the
region's data density (a "High detail" `maxZoom = 15` archive over a dense
suburban/urban downloaded area has far more roads to stitch and far more
`MKMultiPolyline`/`MKMultiPolygon` objects to build than the perf-test's Bellevue
fixture at lower `maxTiles`). The repo already ships a headless benchmark for
exactly this pipeline:

```swift
// MeshtasticTests/MapDataModelTests.swift:239-277
@Test("decode + stitch Bellevue — zoom sweep")
func benchmark() throws {
    for maxTiles in [8, 16, 48] {
        if let stats = OfflineVectorTileProvider.measure(url: url, maxTiles: maxTiles, ...) {
            print("OFFLINE-PERF[z-sweep maxTiles=\(maxTiles)]: \(stats)")
        }
    }
    ...
}
```

The fixture (`bellevue.pmtiles`) isn't present in this worktree so I could not get
real numbers from it during diagnosis, but the existence of a dedicated perf
benchmark ("Overlay count is the dominant SwiftUI-Map cost", `PMTilesMapView.swift:66`)
is the team's own acknowledgment that this pipeline's cost is non-trivial and worth
tracking. This hypothesis alone does **not** explain "offline only," which is why
it's ranked below Hypothesis 1 — but it's the piece of Hypothesis 1 that lives
entirely in this repo's control, and the cheapest to fix regardless of which half of
Hypothesis 1 turns out to dominate.

---

## Ruled out (checked, with evidence)

- **Tile-miss falling back to a synchronous network fetch.** No such fallback exists.
  `PMTilesArchive.tileData` and `MBTilesArchive.tileData` return `nil` on a miss
  (`PMTilesArchive.swift:145-172`, `MBTilesArchive.swift:88-104`); there is no
  `MKTileOverlay` subclass anywhere in `Meshtastic/` despite stale comments
  referencing one (`ClusterMapView.swift:610`, `629`).
- **`MapKit`'s realistic-elevation terrain fetch.** The live code path
  (`ClusterMapView.applyConfiguration`, `ClusterMapView.swift:453-482`) always
  constructs its `MK*MapConfiguration` with `elevationStyle: .flat`. There *is* a
  vestigial `@State var mapStyle` in `MeshMapMK.swift` that gets assigned
  `MapStyle.standard(elevation: .realistic, ...)` in several places
  (`MeshMapMK.swift:60, 503-509, 674-680`) — but that `@State` property is **never
  read by `ClusterMapView`** (it takes no `mapStyle` parameter at all); it's dead
  code left over from a prior SwiftUI-`Map`-based implementation
  (`MeshMapContent.swift:6-8` documents that retirement explicitly: *"The old SwiftUI
  `MeshMapContent`/`OfflineVectorMapContent` renderers were retired with the SwiftUI
  map."*). Worth deleting as cleanup, but not the freeze cause.
- **iCloud-evicted placeholder file triggering a blocking on-demand download inside
  `Data(contentsOf:, options: .mappedIfSafe)`** (`PMTilesArchive.swift:89`). This was
  my initial strongest lead given `Info.plist` sets `UIFileSharingEnabled`,
  `LSSupportsOpeningDocumentsInPlace`, and `UISupportsDocumentBrowser` (Files-app
  visibility), which can coincide with iCloud Drive thinning in other apps. However,
  `Meshtastic.entitlements`/`Meshtastic-Catalyst.entitlements` have **no**
  `com.apple.developer.icloud-container-identifiers`,
  `com.apple.developer.icloud-services`, or `NSUbiquitousContainers` key anywhere
  (checked directly against both entitlements files and `Info.plist`). Without an
  iCloud container entitlement, `Documents/OfflineMaps/*.pmtiles` are plain local
  sandboxed files, not eligible for on-demand iCloud eviction/materialization. Ruled
  out, but flagged because it would be a very easy, very convincing regression to
  introduce later if iCloud Drive document sync is ever added to this app without
  also excluding `OfflineMaps/` from it.
- **Reverse-geocoding / `MKLocalSearch` on the live map.** All `CLGeocoder`/
  `MKLocalSearch` call sites in the map area are in the "download a new offline map"
  search field (`DownloadNewMapView.swift:98-107`, itself requires connectivity to
  be useful) and the "coverage estimate" form (`CoverageEstimateForm.swift:234-238`,
  reachable only from node detail, not from panning/zooming the main map). Neither
  fires from simply viewing a previously-downloaded region.

---

## Recommended fix approach (top hypothesis) — described, not implemented

Two independent, complementary changes, because Hypothesis 1 has two halves and
either alone is a real improvement:

1. **Stop letting MapKit's live basemap fight for resources while the app knows it's
   offline.** Add an `NWPathMonitor`-backed connectivity flag (currently absent from
   this codebase entirely) and thread it into `ClusterMapConfiguration`/
   `ClusterMapView.applyConfiguration`. When the path is `.unsatisfied` (no
   interfaces at all, not merely "expensive"/"constrained"), and the user is looking
   at a region with `enableOfflineTiles` + `offlineRegionOnScreen()` true, avoid
   asking MapKit to keep chasing a live `MKStandardMapConfiguration`/
   `MKHybridMapConfiguration`/`MKImageryMapConfiguration` tile source at all — e.g.
   fall back to whatever the lightest-weight, non-network-dependent base
   configuration MapKit exposes (or a flat neutral fill) for the duration, since the
   app's own offline vector overlay is already providing the basemap detail that
   matters. Restore the live configuration automatically once the path monitor
   reports a satisfied path again.
2. **Get `rebuildOfflineVectorOverlays()`'s `MKShape` construction off the main
   actor.** `OfflineVectorTileProvider.updateIfNeeded()` already does the decode+
   stitch on a background queue and only publishes the lightweight
   `OfflineMapPolygon`/`OfflineMapPolyline` value types to `@MainActor`
   (`PMTilesMapView.swift:145-172`). The MapKit-object construction currently
   happens *after* that hop, synchronously on the main actor, in
   `MeshMapMK.rebuildOfflineVectorOverlays()` (`MeshMapMK.swift:1395-1478`). Move the
   `MKPolygon`/`MKMultiPolygon`/`MKMultiPolyline` allocation itself onto the same
   background queue (or a `Task.detached`) that already does the decode, and hand
   the finished, immutable `[ClusterMapOverlay]` array to the main actor only once
   it's fully built — `MKOverlay` objects are safe to construct off-main since
   they're not touching UIKit/AppKit, only geometry. This shrinks the guaranteed
   main-actor cost of "offline region first comes into view at street zoom" down to
   just `mapView.addOverlay(...)` calls, which is what actually needs to happen on
   main.
3. **Add a coarse watchdog/signpost around the first decode+overlay pass** (e.g.
   `os_signpost` + a timeout-logging `Task`) so that if a worst-case combination
   (huge "High detail" archive, dense urban road grid, zero connectivity, low-end
   device) still takes unacceptably long even after (1) and (2), it degrades to
   "offline basemap not ready yet, showing base map" rather than a silent, unbounded
   hang — and so the next report of this bug comes with real timing data instead of
   "froze, had to force quit."

### How to confirm which half of Hypothesis 1 dominates before implementing

Reproduce with Xcode's Network Link Conditioner set to **100% Loss** (not just
Airplane Mode — Airplane Mode can behave differently from "radio on, zero signal," and
the report explicitly says airplane mode "not necessarily" the trigger), load a
"High detail" downloaded region, zoom from an overview down to the ~1.5mi/z13-14
scale over it, and capture an Instruments **Time Profiler** + **Hangs** trace across
the freeze:

- If the blocked/hot frame is inside CFNetwork/MapKit-private symbols → confirms the
  live-basemap network contention half → prioritize fix (1).
- If the blocked/hot frame is inside `OfflineVectorTileProvider`/
  `rebuildOfflineVectorOverlays`/`ClusterMapView` symbols → confirms the overlay
  construction/rendering half → prioritize fix (2), and pull real numbers from the
  existing `OfflineVectorPerfTests` benchmark (`MeshtasticTests/MapDataModelTests.swift:239-277`)
  against a "High detail" archive sized like the field report's region to quantify
  it.

---

## Fix implemented

This branch implements fixes (1) and (2) from "Recommended fix approach" above (fix
(3), the coarse watchdog, was left out of scope — the chunking fix already gives us
the measurement it would have added, for free, via the log line described below).

### 1. Connectivity-aware live-network extras (`Meshtastic/Helpers/Map/MapConnectivityMonitor.swift`, `MeshMapMK.swift`)

Added `MapConnectivityMonitor`, a small `@MainActor` `ObservableObject` wrapping
`NWPathMonitor` — the connectivity awareness this codebase had *nowhere* at all
before this change (confirmed by the exhaustive grep in the diagnosis above). It
publishes `isOffline`, true only when `NWPathMonitor` reports `.unsatisfied` (no
usable interface at all, not merely slow/lossy — matching the bug report's "no
cellular/data connectivity" distinct from a live-but-weak connection).

`MeshMapMK.clusterConfiguration` now does:

```swift
ClusterMapConfiguration(
    layer: selectedMapLayer == .offline ? .standard : selectedMapLayer,
    showsTraffic: showTraffic && !connectivity.isOffline,
    showsPointsOfInterest: showPointsOfInterest && !connectivity.isOffline,
    ...
)
```

Traffic flow and POI icons are both known live-network MapKit features; neither can
render anything useful with zero connectivity anyway, so this costs nothing visually
and removes one concrete, real source of MapKit tile-fetch contention at exactly the
moment offline viewing is happening.

### 2. Chunked, yielding offline overlay construction (`MeshMapMK.swift`)

`rebuildOfflineVectorOverlays()` used to build every `MKPolygon`/`MKMultiPolygon`/
`MKMultiPolyline` for the whole offline basemap (earth fill, water/park fills, road
casing, road fill, rail/boundary) in one uninterrupted synchronous main-actor pass,
triggered the first time the downloaded region enters the viewport — architecturally
tied to the ~1.5mi/z13-14 "full street grid" zoom tier the diagnosis identified.

That construction now lives in `MeshMapMK.offlineVectorOverlayGroups(coverageAreas:polygons:roads:dark:)`,
an `AsyncStream<[ClusterMapOverlay]>` that yields one chunk per role group (earth,
each fill role, each road pass, rail/boundary — the exact same geometry/styling as
before, only the scheduling changed) and calls `await Task.yield()` between chunks.
`rebuildOfflineVectorOverlays()` consumes it with `for await group in ...`, appending
results as they arrive and guarding against a superseded build (dark-mode flip mid-build,
or a new archive set) with a generation counter. Every chunk still runs on the main
actor — deliberately, to avoid any cross-actor `Sendable` question about handing
non-`Sendable` `MKOverlay` objects between threads — but the run loop now gets a turn
to service touches (and the force-quit gesture) between every group instead of being
blocked for the whole build.

A log line captures the exact evidence a future report like this one would need:

```swift
Logger.services.info("🗺️ [Offline] overlay rebuild: \(groupCount) groups / \(overlayCount) overlays in \(total) (worst uninterrupted chunk \(worstChunk))")
```

## Performance evidence

`MeshtasticTests/OfflineOverlayBuildPerfTests.swift` exercises
`MeshMapMK.offlineVectorOverlayGroups` directly against **synthetic** decode output
(no `.pmtiles` archive needed — this pipeline stage only consumes the already-decoded
`OfflineMapPolygon`/`OfflineMapPolyline` value types `OfflineVectorTileProvider.build`
produces), sized like a dense "High detail" archive's full street grid: 24,000 road
segments across every role + 3,000 polygon fills.

It measures, per chunk, the wall time between yields, and reports:

- **total build time** — this *is* the old code's single uninterrupted main-thread
  block, since the old code did all of this work synchronously in one call.
- **worst single yielded chunk** — this *is* the new code's worst-case single
  uninterrupted main-thread block, since every chunk boundary is now a run-loop
  turn where touches (and the force-quit gesture) get serviced.

Measured on this branch (`xcodebuild test`, iPhone 17 Simulator, `iOS 26`, Debug
configuration):

```
OFFLINE-OVERLAY-PERF: 12 groups / 12 overlays over 3000 fills + 24000 road segments
  total build time (== worst-case main-thread block BEFORE this fix): 26.73 ms
  worst single yielded chunk (== worst-case main-thread block AFTER this fix): 5.85 ms
  max-single-block reduction: 4.6x
  per-chunk breakdown (ms): 5.85, 3.52, 0.37, 0.38, 4.43, 1.55, 1.47, 2.17, 1.64, 1.54, 1.51, 2.03
```

**4.6x reduction in the single longest uninterrupted main-thread block**, on a
synthetic dataset already sized for a dense archive — the effect gets *more*
pronounced, not less, on denser/larger real archives, since the fix turns an
O(total work) single block into an O(total work / group count) worst-case block, and
group count (12) is fixed regardless of how much data is in each group. A field
device hitting a multi-hundred-millisecond or multi-second freeze under the
combined-contention scenario in Hypothesis 1 would see the same proportional
reduction in its single longest blocking span — the number that actually determines
whether the UI reads as "a bit janky" versus "frozen, needs force-quit."

Both `OfflineOverlayBuildPerfTests` tests pass, along with the pre-existing
`OfflineVectorPerfTests` and `MapDataMetadataTests` suites (run via
`xcodebuild ... test-without-building -only-testing:...`); a full `xcodebuild build`
and `build-for-testing` of the `Meshtastic` scheme both succeed cleanly with no new
warnings (including no `Sendable`/concurrency warnings from `SWIFT_STRICT_CONCURRENCY
= targeted` on this file) introduced by either change.

---

## Post-review fixes (`meshtastic-reviewer`)

Ran the `meshtastic-reviewer` agent against this diff before opening the PR. Verdict was
🔴 changes-required, with one real blocking issue and a few nits, all addressed below.

**Blocking — fixed.** `MeshMapMK.offlineVectorOverlayGroups`'s producer `Task` and
`rebuildOfflineVectorOverlays`'s consumer `Task` were two independent, unstructured
tasks with no parent/child relationship. The consumer's `generation` guard stopped a
superseded build from being *applied*, but did nothing to stop the *producer* from
continuing to run (and burn main-actor CPU) after being superseded — e.g. a dark-mode
flip landing shortly after `offlineVectors.revision` bumps (both feed the same
`overlayInputsKey`) could leave two builds interleaving chunk-by-chunk on the same
actor, doubling the exact main-thread cost this fix exists to reduce. Fixed by wiring
real cancellation through `AsyncStream.onTermination` (cancels the producer `Task` when
the consumer stops iterating) plus a `guard !Task.isCancelled` before every
`continuation.yield(...)` in the producer, so a superseded build now actually stops
doing work instead of just being ignored.

**Nit — fixed.** The chunked rebuild cleared `offlineVectorOverlays = []` before the
first chunk landed, then appended chunks in as they arrived — a visible regression from
the old code's atomic swap (the old, still-complete basemap stayed on screen until the
new one was fully built). Fixed by staging into a local `var staged` across the `for
await` loop and assigning `offlineVectorOverlays = staged` once, after the stream
finishes — keeps the chunked/yielding *construction* benefit while restoring the
atomic-swap *display* behavior.

**Nit — fixed.** New `disable_print` SwiftLint warning in
`OfflineOverlayBuildPerfTests.swift`; bracketed the perf-evidence `print` with the same
`// swiftlint:disable disable_print` / `// swiftlint:enable disable_print` pragma pair
`OfflineVectorPerfTests` already uses in `MapDataModelTests.swift`.

**Coverage gap — fixed.** Added `darkModeSkipsCasingGroups`, asserting the dark-mode
group count (9, not light mode's 12 — `offlineRoadCasingColor` returns `nil` for every
role in dark mode, dropping the 3 casing groups) so a regression in that role-skip
logic shows up as a count mismatch instead of only being covered in light mode.

**Docs advisory — addressed.** Added a short "Offline Maps" section to
`docs/developer/architecture.md` describing the pipeline (`OfflineMapManager` →
`OfflineVectorTileProvider` → `MeshMapMK.offlineVectorOverlayGroups` →
`MapConnectivityMonitor`) per the reviewer's read of the `.github/copilot-instructions.md`
docs-sync table — this diff introduces a new standing module (`MapConnectivityMonitor`)
and a new concurrency pattern for the overlay pipeline, which the docs guidance calls
out as doc-worthy even though there's no user-visible string/flow change.

**Deferred (explicitly low-priority per the reviewer).** `MapConnectivityMonitor`
spawns one unstructured `Task` per `NWPathMonitor.pathUpdateHandler` callback; the
reviewer noted these aren't strictly ordering-guaranteed across independently-spawned
tasks, but called it "practically inconsequential" for a rarely-changing connectivity
flag (any transient reordering self-corrects on the next resolved update) and only
worth revisiting "if this pattern gets reused somewhere flappier." Left as-is.

Re-verified after fixes: `swiftlint lint --quiet` clean (zero new warnings; the
pre-existing `MeshMapMK` `type_body_length` warning is unrelated to this diff, confirmed
via `git stash` diff-of-diff), `xcodebuild build-for-testing` succeeds, and all 11 tests
across `OfflineOverlayBuildPerfTests` / `OfflineVectorPerfTests` / `MapDataMetadataTests`
pass. Updated perf run after the fixes (same synthetic workload as above):

```
OFFLINE-OVERLAY-PERF: 12 groups / 12 overlays over 3000 fills + 24000 road segments
  total build time (== worst-case main-thread block BEFORE this fix): 24.09 ms
  worst single yielded chunk (== worst-case main-thread block AFTER this fix): 4.53 ms
  max-single-block reduction: 5.3x
```
