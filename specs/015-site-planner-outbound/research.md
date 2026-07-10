# Research: Site Planner Outbound Coverage Estimate

All findings below were verified against the actual current source (`origin/main` of both `meshtastic/Meshtastic-Apple` and `meshtastic/meshtastic-site-planner`, and the local checkout of `meshtastic-site-planner` fast-forwarded via `git show origin/main:...` reads) as of 2026-07-09, not against the design issue's paraphrase — the issue's mention of a `&bridge=1` query flag turned out not to exist in the shipped code (see Decision 1).

## 1. The native-bridge contract (exact, from `meshtastic-site-planner` `src/map/export.ts` @ `origin/main`)

**Decision**: The bridge is pure JS feature-detection, not a query flag.

```ts
export function postCoverageToBridge(site: Site): void {
  const bridge = (globalThis as { __meshtasticNative?: { onCoverage?: (geojson: string) => void } })
    .__meshtasticNative;
  if (typeof bridge?.onCoverage === 'function') {
    try {
      bridge.onCoverage(JSON.stringify(coverageFeatureCollection(site)));
    } catch (error) {
      console.error('postCoverageToBridge: native bridge threw', error);
    }
  }
}
```

Called unconditionally from `store.ts` after **every** successful simulation completion (autorun via `run=1`, or a normal manual "Run" click) — right before the transmitter name gets randomized for the next run, so the payload still carries the requested site name. No-op (silently) if `window.__meshtasticNative.onCoverage` isn't a callable function.

**Rationale**: There is no `bridge=1` param to send — the design issue's mention of one does not match the shipped code. Presence of a real, callable `onCoverage` function is the only gate.

**Implication for the WKWebView side**: `WKScriptMessageHandler` cannot be called directly as `window.__meshtasticNative.onCoverage(...)` — JS can only reach it via `window.webkit.messageHandlers.<name>.postMessage(payload)`. A `WKUserScript` must be injected at `.atDocumentStart` (before the planner's own JS runs) that defines:

```js
window.__meshtasticNative = {
  onCoverage: function (geojson) {
    window.webkit.messageHandlers.meshtasticCoverageBridge.postMessage(geojson);
  }
};
```

The registered `WKScriptMessageHandler`'s `userContentController(_:didReceive:)` then receives `message.body` as a Swift `String` (the JSON-encoded `FeatureCollection` — a **string**, not a dictionary; must be `Data(string.utf8)`-decoded before handing to the existing GeoJSON pipeline).

**Alternatives considered**: Polling the WebView's DOM/JS state instead of a message handler — rejected, WKScriptMessageHandler is the standard, purpose-built mechanism and avoids polling races.

## 2. The flat query contract (exact field list, from `permalink.ts` @ `origin/main`)

**Decision**: Full field list to support, grouped exactly as the source groups them (this determines the form's section layout, matching FR-004's "mirror the reference tool's grouping"):

| Query key | Section | Type | Notes |
|---|---|---|---|
| `lat`, `lon` | transmitter | number | required for any run |
| `tx_power` | transmitter | number (watts) | |
| `tx_freq` | transmitter | number (MHz) | |
| `tx_height` | transmitter | number (m AGL) | |
| `tx_gain` | transmitter | number (dBi) | |
| `name` | transmitter | string | becomes `properties.name` on the resulting GeoJSON |
| `rx_sensitivity` | receiver | number (dBm) | |
| `rx_height` | receiver | number (m) | |
| `rx_loss` | receiver | number (dB) | |
| `max_range` | simulation | number (km) | maps to `simulation_extent` |
| `situation_fraction`, `time_fraction` | simulation | number | ITM statistical params, advanced/expert only |
| `high_res` | simulation | boolean (`1`/`true`) | maps to `high_resolution` |
| `clutter_height`, `ground_dielectric`, `ground_conductivity`, `atmosphere_bending` | environment | number | advanced/expert only |
| `radio_climate` | environment | enum | validated against a fixed code list; unknown → default silently |
| `polarization` | environment | enum | validated against a fixed code list; unknown → default silently |
| `min_dbm`, `max_dbm`, `overlay_transparency` | display | number | |
| `color_scale` | display | enum: `plasma`(default) `viridis` `CMRmap` `cool` `turbo` `jet` | unknown → `plasma` |
| `run` | — | boolean (`1`/`true`) | autorun on load |

`rx_gain` is deliberately not part of the contract (ignored for area coverage in the upstream engine).

**Rationale**: Matching the exact key names/sections lets the query-string builder be a straight 1:1 mapping with no translation layer, and matches Android's already-shipped section grouping (Site/Transmitter, Receiver, Simulation Options, Display) for cross-platform consistency.

**Alternatives considered**: A base64 `#cfg=` blob (the general permalink mechanism) — rejected for this use case; the flat contract exists specifically so a client "never needs the planner's internal schema" per the source comment, and is simpler to construct from Swift.

## 3. Existing iOS code to extend (not replace)

**Decision**: Reuse `MapDataManager` and `GeoJSONOverlayConfig`/`GeoJSONOverlayManager` unchanged for storage/styling; add one new entry point.

- `Meshtastic/Helpers/MapDataManager.swift` (current `origin/main`, already includes the `importFromRemote(urlString:)` http/file-URL path added for the inbound-import work) has **no method that accepts already-in-memory GeoJSON data** — only URL-based entry points (`processUploadedFile(from: URL)`, `importFromRemote(urlString:)`). Every entry point ultimately funnels through `processUploadedFile`, which copies from a source `URL` into `MapData/user_uploaded/`, validates it as a `FeatureCollection`, and appends a `MapDataMetadata` record to `upload_history.json`.
- **Plan**: add `importFromData(_ data: Data, suggestedName: String) async throws -> MapDataMetadata`, mirroring exactly what `importFromRemote` already does for an HTTP response body — write `data` to a temp file, `defer` its removal, and hand it to the existing `processUploadedFile(from:)`. This is the smallest possible change to this file and reuses 100% of the existing validation/persistence/notification logic.
- `GeoJSONOverlayConfig.swift`'s simplestyle/`color`-fallback styling (fixed for Site Planner exports in #2037) needs **no changes** — a bridge-delivered `FeatureCollection` uses the identical `fill`/`stroke`/`color` property shape as a file-based export, since it's produced by the same `coverageFeatureCollection()` function on the planner side either way.
- `GeoJSONOverlayManager.shared.clearCache()` exists and is already called by `MapDataManager.deleteFile`; the new `importFromData` path should invalidate the same cache the way `processUploadedFile` already does (it clears `activeFeatureCollection` internally — confirm this covers `GeoJSONOverlayManager`'s cache too, or call `clearCache()` explicitly, during implementation).

**Rationale**: The styling bug (#2037) and the file-import pipeline are already correct and tested; this feature is purely a new *producer* of the same GeoJSON shape, not a new consumer.

## 4. Prefill data sources

**Decision**: Prefill source fields, confirmed to exist on `LoRaConfigEntity` (`Meshtastic/Model/ConfigModels.swift`): `txPower` (Int32, dBm; `0` is the firmware's "use region max" sentinel — confirmed by the existing `LoRaConfig.swift` settings view, which special-cases `txPower == 0` to show "Max Transmit Power" but does **not** itself resolve it to a number), `regionCode`, `modemPreset`, `overrideFrequency`, `bandwidth`, `spreadFactor`, `codingRate`.

- **Frequency**: `Meshtastic/Helpers/LoRaChannelCalculator.swift` already has `radioFrequencyMHz(slot:)`, which correctly derives the actual operating frequency from region + modem preset + channel slot. Reuse this directly for `tx_freq` — do not reimplement.
- **Transmit power in watts**: no existing helper resolves the `txPower == 0` sentinel to an actual wattage (region-specific legal max). **Open item for planning/tasks**: a small new helper mapping `regionCode` → max legal EIRP, converting the firmware's dBm value (or the resolved regional max) to watts for the `tx_power` query field. Must not guess regional power limits — source them from the same `protobufs` region table the firmware itself uses (`Config.LoRaConfig.RegionCode`), not invented.
- **Receiver sensitivity**: no existing helper. Standard LoRa sensitivity is a function of spreading factor + bandwidth (+ a fixed noise-figure margin); this is genuinely new, well-defined DSP-textbook math, not a guess — implement as a small pure function taking `spreadFactor`/`bandwidth` and returning dBm, and unit-test it against known reference values (e.g. SF7/BW125 ≈ ‑124 dBm) rather than inventing a table.

**Rationale**: Reuse what exists (`radioFrequencyMHz`), and flag what doesn't as small, well-scoped, independently testable new logic rather than open-ended research risk.

## 5. Mac Catalyst WKWebView headless-JS risk

**Decision**: Treat as an **open implementation risk to verify early in `tasks.md`**, not an assumed-safe default.

**Rationale**: WKWebView is available and generally consistent under Mac Catalyst, but an off-screen/zero-frame WKWebView's JS execution and `WKUserContentController` message delivery under Catalyst's AppKit-hosted `NSView` bridging has known edge cases elsewhere in WebKit (e.g. some Catalyst builds have historically needed the WebView attached to a visible view hierarchy, even at 1×1 size, for its render/JS pump to run reliably in the background). This project already conditionally special-cases Mac Catalyst elsewhere (`#if targetEnvironment(macCatalyst)` in `MarketingCapture.swift`, entitlements split, etc.), so a fallback (e.g. attaching the hidden WebView to an actually-present-but-invisible view rather than an unattached one) is a reasonable, in-pattern contingency if the zero-frame approach doesn't work — confirm empirically, do not assume either way.

**Alternatives considered**: Skip Mac Catalyst for v1 — rejected; Assumption in spec.md and Constitution Principle VII both treat full platform parity as a firm requirement, not a stretch goal.

## 6. Design Standards doc

**Resolved during implementation** (T002): the fetch "failure" during planning was a red herring — `meshtastic_design_standards_latest.md` is a **symlink**, and GitHub's raw server returns a symlink's raw content as literally the target filename string (`meshtastic_design_standards_v1_4.md`), not the file it points to. Fetching that real target worked immediately (`gh api repos/meshtastic/design/contents/standards` lists it; `curl` on the raw URL for `_v1_4.md` specifically returns the full 426-line doc). Lesson: always resolve the real filename via the repo's directory listing rather than trusting `_latest.md` to redirect.

**Findings actually relevant to this feature** (v1.4, full doc — not just a summary):

- **§10 Units, Measurement & Locale — directly binding on `CoverageEstimateForm`.** "The client must never expose raw metric values to users who expect imperial... conversion happens only at the presentation layer... via `Measurement` + `MeasurementFormatter` / `.formatted(.measurement(...))`." This feature's height/range/distance fields (`tx_height`, `rx_height`, `max_range`) are metric-only in the query contract (§ contracts/query-contract.md) — **the form must store/send metric values but display them through `Measurement<UnitLength>` + a locale-aware formatter**, not a hardcoded "m"/"km" suffix. This changes T015/T023: each height/range control needs a `Measurement`-backed input, not a plain `Double` + string label. dBm/dBi/MHz/watts have no OS conversion API (they're not general-purpose physical units `Measurement` models) and are used as-is, consistent with §10.4's "universal units" carve-out for domain-specific units without a locale-conversion concept.
- **§6 Information Architecture — "use subtext to explain technical settings in simple, non-technical terms."** The advanced/Environment section (T023: `clutter_height`, `ground_dielectric`, `ground_conductivity`, `atmosphere_bending`, `situation_fraction`, `time_fraction`) is dense RF jargon even by this app's own standards. Each advanced field needs a plain-language subtitle (mirroring the doc's own "Hop Limit: the number of times..." example), not just a raw label.
- **§3 Dynamic Layout & Conditional Visibility — "Null Data Suppression... avoid 'N/A' or '0' placeholders."** When no radio is connected (FR-003's fallback path), fields without a real device-derived value should not render as a misleading "0" — either hide the field's device-derived-value affordance or clearly mark it as "using default," not silently show a zero that looks like a read value.
- **§5 Vision-Centric Design — 44×44pt minimum touch targets, Dynamic Type up to 200% without clipping, and "Desktop and Web clients must provide hover tooltips for all icon-only buttons."** Directly binding on the map-toolbar control (T020), which is icon-only — needs a tooltip under Mac Catalyst specifically (iOS/iPadOS don't have hover, but Catalyst runs under a pointer-capable environment).
- **§9 Color Usage Rules** governs any UI chrome this feature draws itself (form section headers, buttons) — but the coverage overlay's own rendering is unaffected (that palette is the Site Planner's scientific colormap, e.g. `jet`/`turbo`/`plasma`, not this app's brand palette, and is explicitly out of scope for §9's rules, which govern app UI chrome, not scientific data visualization).

No brand-palette conflict: the six `color_scale` options are inherent to what's being visualized (an RF signal-strength heatmap) and are a different concern from the app's own Material/brand color system.
