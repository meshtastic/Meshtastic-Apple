# Handoff: traceroute flyover + Mac Catalyst re-render loop

Worktree branch: `feat/traceroute-capture-all-and-snapshots` (based on / merged with `feat/pmtiles-mapkit-shim`).
(Delete this file when done — it's just a handoff note, not part of the feature.)

## What's done & committed
- **Capture-all + global log + position snapshots** (commit `43075548`): `handleTraceRouteApp` saves every full response (initiated + observed); `AllTraceRoutesLog` under Settings ▸ Logging; `TraceRouteNodePositionEntity` snapshots each node's `latestPosition` at response time.
- **Traceroute on the map + 3D flyover** (commit `26eeae92`): forward (solid)/return (dashed) polylines + origin/target markers in `MeshMapMK`; `meshtastic:///map?tracerouteId=<id>` deep link (`MapNavigationState.traceRoute`); "Show on Map" buttons in both logs; `TraceRouteFlyover` (CADisplayLink camera tour); `ClusterMapView.onMapCreated` hook; `PerformanceSeedData` seeds mappable routes.
- **Pulse-halo fix** (`05d95391`): `AnimatedNodePin` pulse is a `.background` driven by `TimelineView` (was drifting). Verified on Catalyst.

## UNCOMMITTED work-in-progress (partial fix for the loop, builds clean)
- `ClusterMapView`: added `suppressRegionUpdates` — when true, `regionDidChangeAnimated` does NOT write the `region` binding (so caller-driven camera moves don't re-render `body`).
- `MeshMapMK`: passes `suppressRegionUpdates: flyover.isFlying`; `frameTraceRoute()` now drives `flyover.mapView?.setRegion(_, animated:false)` directly instead of writing `visibleRegion`.

## THE BUG (open)
On **Mac Catalyst**, showing a trace route on the map over seeded nodes drives `MeshMapMK.body` into a re-render loop → 100% CPU → beachball. **Fine on the iOS simulator.**
- Hot path (two `sample` runs agree): `MeshMapMK.body` → `visiblePositionState` (MeshMapMK.swift:172) → `visiblePositions` → `filteredPositions` (filters every node) — re-evaluated continuously.
- The framing fix above removed the *initial* spiral (settles ~2s) but a **second trigger** re-spirals once a route is shown.
- Suspect amplifiers in `body` / `.onChange(of: positionState.key)` (MeshMapMK.swift ~414–462): each key change runs `refreshVisiblePositionSnapshots` (sets `visiblePositionSnapshots`, `spreadOverrides`, `mapOverlays`) **and** `filters.fallbackLocation = activeDeviceCoordinate` (mutates the shared `NodeFilterParameters` `@ObservedObject` → another `body` render). Need to find what keeps `positionState.key` (or an observed object) changing.
- Likely real fix: make `visiblePositionState` not recompute the heavy filter on every `body` eval (cache it), and/or stop the onChange handler from mutating observed state that re-triggers `body`. This is pre-existing map architecture, not the flyover code per se.

## Reproduce / drive the Catalyst app (no device needed)
```sh
# build
xcodebuild build -project Meshtastic.xcodeproj -scheme Meshtastic \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/mesh-dd-cat -allowProvisioningUpdates
APP=/tmp/mesh-dd-cat/Build/Products/Debug-maccatalyst/Meshtastic.app
# launch windowed + seed (launchctl env is how a GUI app gets the seed count)
pkill -9 -f "Debug-maccatalyst/Meshtastic.app"; launchctl setenv MESHTASTIC_PERF_SEED_NODES 30
open "$APP" --args --meshtastic-perf-seed --meshtastic-perf-reset
# once idle, load a route on the map (id = node index, multiples of 25 exist: 25/50/75)
open "meshtastic:///map?tracerouteId=25"
# sample the hang
sample "$(pgrep -f Debug-maccatalyst/Meshtastic | head -1)" 2 -file /tmp/s.txt
```
Flyover ▶/⏹ is in the route banner at the top of the map. Launching the raw binary directly gives NO window ("Connection is invalid") — must use `open`.

Backup of pre-merge branch state: `backup/tr-before-pmtiles-rebase`.
