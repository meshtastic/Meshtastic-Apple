# Contract: Outbound Query URL (app → Site Planner)

**Direction**: App constructs a URL, loads it in a hidden WKWebView.
**Source of truth**: `meshtastic-site-planner` `src/permalink.ts`, function `decodeSharedQuery` / `sharedRunRequested` (verified against `origin/main`, see [research.md](../research.md) §2).
**Base**: `https://site.meshtastic.org/`

## Construction rule

Only include keys the user actually set or that have a defined value from prefill — omitted keys fall back to the planner's own factory defaults (`mergeParams` merges section-by-section, so a partial query is always safe). Always include `run=1` — this feature never wants the planner sitting idle waiting for a manual click.

## Query keys

Numeric keys are sent as plain decimal strings (`Double`/`Int`, no units suffix, no thousands separators). Booleans are `1` (never send `0`/`false` — simply omit the key). Enum keys are sent as their exact lowercase code string; the planner ignores anything not in its known list and falls back to default, so an invalid enum value is *silently wrong*, not an error — the client MUST NOT offer values outside the known lists below.

| Key | Type | Example |
|---|---|---|
| `lat`, `lon` | number | `47.6062`, `-122.3321` |
| `name` | string, URL-encoded | `U-District%20Solar` |
| `tx_power` | number (watts) | `0.1` |
| `tx_freq` | number (MHz) | `915` |
| `tx_height` | number (m) | `2` |
| `tx_gain` | number (dBi) | `2` |
| `rx_sensitivity` | number (dBm), range −150…−30 | `-130` |
| `rx_height` | number (m) | `1` |
| `rx_loss` | number (dB) | `2` |
| `max_range` | number (km), ≤150 (≤70 if `high_res=1`) | `30` |
| `high_res` | bool | `1` |
| `situation_fraction`, `time_fraction` | number | (advanced; omit unless user expands the advanced section) |
| `clutter_height`, `ground_dielectric`, `ground_conductivity`, `atmosphere_bending` | number | (advanced; omit unless user expands) |
| `radio_climate` | enum | `continental_temperate` (see code list below) |
| `polarization` | enum | `vertical` / `horizontal` |
| `min_dbm`, `max_dbm` | number (dBm) | `-130`, `-80` |
| `overlay_transparency` | number (%) | `50` |
| `color_scale` | enum | `plasma` `viridis` `CMRmap` `cool` `turbo` `jet` |
| `run` | bool | `1` (always) |

**`radio_climate` code list** and **`polarization` code list**: pull the exact accepted string values from `meshtastic-site-planner`'s `CLIMATE_CODES` / `POLARIZATION_CODES` constants (`src/permalink.ts` or wherever they're actually defined — confirm the exact export location during implementation) rather than hand-copying them into this doc, since they're an implementation detail of an external repo that could shift; the client-side enum picker's option list should be sourced from (or kept in lockstep with) those constants, not invented independently.

## Non-goals

- No `bridge=1` key — it does not exist in the shipped contract (see research.md §1). Do not add it "just in case."
- No `#cfg=` base64 permalink blob — that's a different, more general mechanism this feature doesn't need.
- `rx_gain` is never sent — the upstream engine ignores it for area coverage.
