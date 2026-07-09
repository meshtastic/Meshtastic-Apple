# Phase 1 Data Model — Site Planner Outbound Coverage Estimate

This feature adds **no new persisted (SwiftData) entity**. It produces the same `GeoJSONFeatureCollection` shape the existing inbound-import pipeline already consumes and stores, and it reads existing radio-config entities for prefill. The only new types are transient, in-memory value types describing a single estimate run.

## Persisted (SwiftData) — existing, reused, unchanged

### `LoRaConfigEntity` (`Meshtastic/Model/ConfigModels.swift`) — read-only source for prefill
- `txPower: Int32` (dBm; `0` = firmware sentinel for "use region max" — not yet resolved to watts by any existing code)
- `regionCode: Int32`, `modemPreset: Int32`, `overrideFrequency: Float`, `bandwidth: Int32`, `spreadFactor: Int32`, `codingRate: Int32`, `usePreset: Bool`

### `MapDataMetadata` (`Meshtastic/Helpers/MapDataManager.swift`) — the persisted record for a saved overlay
No changes. A completed estimate becomes one of these via the new `importFromData` entry point (see [contracts/native-bridge-contract.md](./contracts/native-bridge-contract.md)) — from storage's perspective it is indistinguishable from a file that was imported by hand.

### `GeoJSONFeatureCollection` / `GeoJSONFeature` (`Meshtastic/Helpers/GeoJSONOverlayConfig.swift`) — the wire/storage shape
No changes. Same `fill`/`stroke`/`fill-opacity`/legacy `color` property shape whether the collection arrived via file import or via the bridge — both are produced by the same function on the planner side.

## Transient (in-memory only) — new

### `CoverageEstimateParameters`
The full set of user-adjustable inputs for one run, grouped exactly like the query contract's sections (see [contracts/query-contract.md](./contracts/query-contract.md)) so the form's section layout maps 1:1 onto it:

- **Site/Transmitter**: `name: String`, `latitude: Double`, `longitude: Double`, `transmitPowerWatts: Double`, `transmitFrequencyMHz: Double`, `antennaHeightMeters: Double`, `antennaGainDBi: Double`
- **Receiver**: `receiverSensitivityDBm: Double`, `receiverHeightMeters: Double`, `receiverLossDB: Double`
- **Simulation**: `maxRangeKm: Double`, `highResolutionTerrain: Bool`, `situationFraction: Double?`, `timeFraction: Double?` (last two: advanced/expert fields, default-hidden per FR-004's "mirror the reference tool's grouping," which treats them as an advanced sub-section)
- **Environment** *(advanced)*: `clutterHeightMeters: Double?`, `groundDielectric: Double?`, `groundConductivity: Double?`, `atmosphereBending: Double?`, `radioClimate: RadioClimate?`, `polarization: Polarization?`
- **Display**: `minDBm: Double`, `maxDBm: Double`, `overlayTransparencyPercent: Double`, `colorScale: ColorScale` (`plasma` default, `viridis`, `CMRmap`, `cool`, `turbo`, `jet`)

Not `Codable`/persisted as a model — it exists only for the duration of one form session and is discarded once the request is sent (or the resulting overlay is kept via the normal `MapDataMetadata` path).

**Validation rules** (client-side, before constructing the query URL):
- `latitude`/`longitude` required and within valid ranges — cannot submit without a position (FR-001/FR-002's precondition).
- `receiverSensitivityDBm` within [-150, -30] (matches the reference tool's own accepted range; out-of-range values would silently misbehave upstream).
- `maxRangeKm` ≤ 150, or ≤ 70 when `highResolutionTerrain` is true (reference tool's own cap).
- Enum fields (`radioClimate`, `polarization`, `colorScale`) constrained to the known code lists documented in [research.md](./research.md) §2 — anything else is meaningless to send (the reference tool would just ignore it and fall back to its default), so the picker UI should only ever offer valid values rather than needing runtime validation.

### `CoverageEstimateState`
The lifecycle of one in-flight (or completed/failed) estimate, driving FR-007/FR-008/FR-009 (in-progress indicator, cancellation, error surfacing):

- `.idle`
- `.running(startedAt: Date)`
- `.succeeded(overlay: MapDataMetadata)`
- `.failed(reason: CoverageEstimateError)`
- `.canceled`

`CoverageEstimateError` cases: `.timeout`, `.noBridgeResponse` (page loaded but never called back — e.g. the simulation failed on the planner side, or the page itself failed to load), `.invalidResponse` (bridge called back with something that doesn't decode as a `FeatureCollection`), `.noNetwork`.

Only one `CoverageEstimateState` may be `.running` at a time app-wide (FR-007) — a singleton coordinator (not a per-view `@State`) owns this, so starting a second estimate while one is running is rejected at the source rather than merely hidden by disabling a button.
