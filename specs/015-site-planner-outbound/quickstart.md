# Quickstart — Site Planner Outbound Coverage Estimate (implement & validate)

## Prerequisites
- Xcode (latest), a checkout on branch `015-site-planner-outbound`.
- **Before any UI work** (estimate form, map control, node-detail action): fetch and review the [Meshtastic Client Design Standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md) fresh (Constitution VIII) — do not reuse a cached summary from planning; it could not be reliably fetched during this planning pass (see research.md §6).
- Rebase this branch onto current `main` once the inbound-import branch (`feat/open-in-geojson-import`, #2056) merges, to pick up any shape changes to `MapDataManager` before adding `importFromData`.
- No `gen_protos.sh` run needed — no protobuf schema changes in this feature.

## Build & test
```bash
xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
  -only-testing:MeshtasticTests/CoverageEstimateParametersTests \
  -only-testing:MeshtasticTests/LoRaSensitivityTests \
  -only-testing:MeshtasticTests/MapDataManagerImportFromDataTests
```
New `.swift` files MUST be registered in `project.pbxproj` (the `Meshtastic/` group is not synchronized) or they will silently fail to compile. Use Swift Testing (`@Suite`/`@Test`/`#expect`), not XCTest.

## Implementation order (suggested)

1. **Pure logic first, no UI, no WebView**: `CoverageEstimateParameters` + its validation rules (data-model.md), the region→max-power-in-watts helper, and the modem-preset→sensitivity helper. Fully unit-testable against known reference values without a device or network.
2. **`MapDataManager.importFromData(_:suggestedName:)`**: smallest possible addition, mirrors `importFromRemote`'s temp-file-then-`processUploadedFile` pattern exactly. Unit-test with a canned `FeatureCollection` string.
3. **The bridge itself**: a small, self-contained coordinator type owning a hidden `WKWebView` + `WKUserScript` injection + `WKScriptMessageHandler`, exposing an async "run this request, return a result or throw" surface to callers — build and manually verify this in isolation (e.g. from a debug-only trigger) before wiring any UI to it. **Verify the Mac Catalyst headless-JS risk here first** (research.md §5) — if a zero-frame WKWebView doesn't reliably execute JS under Catalyst, this is the point to discover it and adjust (e.g. attach to an invisible-but-present view) before building UI on top of a broken assumption.
4. **`CoverageEstimateState` coordinator** (singleton, one in-flight run app-wide) wrapping step 3 with cancellation + timeout.
5. **UI**: node-detail action first (P1), then map-toolbar control (P2), then the advanced/simulation/environment sections (P3) — matches the spec's story priority, and each is independently demonstrable once its predecessor exists.

## Manual validation

- **Happy path (P1)**: open a node with a known position and a connected radio → start the estimate action → submit with defaults → confirm a new named overlay appears on the mesh map, styled like any other GeoJSON import, without any browser or share sheet appearing.
- **No radio connected**: repeat with no radio connected → form must still open and be submittable using factory defaults, not block.
- **Map-location entry (P2)**: from the map (not a node), start the estimate control → confirm the prefilled position matches the map view, not `(0, 0)` or a stale value.
- **Cancellation**: start an estimate, cancel before it completes → UI returns to idle, no overlay is added, and a second estimate can be started immediately after.
- **Concurrency guard**: start an estimate, then immediately try to start a second one (from either entry point) → rejected/blocked, not queued or silently ignored.
- **Advanced params (P3)**: change `color_scale` to `jet` and reduce `max_range` → resulting overlay visibly uses the new palette and a visibly smaller extent than a default run at the same location.
- **Failure/timeout**: force a failure (e.g. airplane mode mid-request) → a clear, specific error is shown, not a silent hang or a crash.
- **Mac Catalyst**: repeat the happy path on a Mac Catalyst build specifically — do not assume iPhone/iPad success implies Catalyst success (research.md §5).

## Definition of done
- Constitution Check re-passes (esp. VIII design standards fetched live for each new screen, IV logging via `Logger`, not `print`, VII platform parity including Catalyst).
- All new suites green; existing GeoJSON-import and map-overlay suites unregressed.
- SC-001 (≤4 steps, no browser) and SC-002 (≥90% of default-value submissions succeed) demonstrated manually; SC-003/SC-004 confirmed by inspection across form factors.
