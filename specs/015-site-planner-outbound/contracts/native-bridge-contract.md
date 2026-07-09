# Contract: Native Bridge Callback (Site Planner → app)

**Direction**: The planner's own JS calls into the app.
**Source of truth**: `meshtastic-site-planner` `src/map/export.ts`, function `postCoverageToBridge` (verified against `origin/main`, see [research.md](../research.md) §1).

## The exact call the planner makes

```js
window.__meshtasticNative.onCoverage(jsonString)
```

- Called **iff** `typeof window.__meshtasticNative?.onCoverage === 'function'` at the moment a simulation completes (autorun or manual) — pure feature detection, no query flag gates it.
- `jsonString` is `JSON.stringify(FeatureCollection)` — **a string**, not a live object. The `FeatureCollection` is RFC 7946, styled with simplestyle `fill`/`stroke`/`fill-opacity` (+ legacy `color` fallback), carrying `properties.generator` and `properties.name` as top-level foreign members (same shape the existing inbound-import pipeline already parses via `GeoJSONOverlayConfig` — no new parsing logic needed on that side).
- No return value is read by the caller, and the call is wrapped in the planner's own `try/catch` — a throwing/missing bridge is silently swallowed on the JS side. **The app-side handler therefore has no way to signal "I received it" back to the planner**; a "did the estimate actually arrive" indicator must be inferred entirely on the native side (message received vs. a timeout with no message).
- If the simulation **fails** (not just "no coverage"), `postCoverageToBridge` is never called at all — there is no failure-callback counterpart. A timeout is the only signal the app gets for "the planner never called back," and it cannot distinguish "still computing," "computation failed," and "page failed to load" from that alone. Surfacing a more specific error than "no response" to the user may require also observing WKWebView's own `navigation`/load-failure delegate callbacks as a secondary signal.

## Required native-side shim

Because `WKScriptMessageHandler` is only reachable via `window.webkit.messageHandlers.<name>.postMessage(...)`, not as a bare global function, the app must inject a shim **before** the planner's own script executes:

```js
window.__meshtasticNative = {
  onCoverage: function (geojson) {
    window.webkit.messageHandlers.meshtasticCoverageBridge.postMessage(geojson);
  }
};
```

- Inject via `WKUserScript(source:, injectionTime: .atDocumentStart, forMainFrameOnly: true)`, added to the `WKWebViewConfiguration.userContentController` **before** the webview is created/navigated.
- Register a `WKScriptMessageHandler` under the exact name used in `postMessage` above (`meshtasticCoverageBridge` — arbitrary but must match both sides), via `userContentController.add(_:name:)` on the same `userContentController`.
- The handler's `userContentController(_:didReceive:)` receives `WKScriptMessage.body` as a Swift `String` — decode with `Data(string.utf8)` before feeding it to the existing GeoJSON import path (see below).

## Where the result goes on success

`onCoverage`'s string body → `Data(jsonString.utf8)` → `MapDataManager.importFromData(_:suggestedName:)` (new method, see [research.md](../research.md) §3 — thin wrapper around the existing `processUploadedFile(from: URL)` after writing to a temp file, exactly like `importFromRemote` already does for HTTP responses) → existing validation/styling/persistence, unchanged.

## Timeout policy

Not specified upstream — the app must pick and enforce its own timeout (research/tasks: pick a value long enough for a large/high-res simulation to genuinely finish, short enough that FR-007's "clear in-progress state" doesn't mean an indefinite spinner; consider surfacing elapsed time rather than a hard cutoff, given simulations can legitimately take a while at `high_res` + large `max_range`).
