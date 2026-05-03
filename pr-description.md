## What changed?

Adds **Local Mesh Discovery** (Settings → Local Mesh Discovery) — an automated multi-preset RF scanner that cycles through LoRa modem presets to audit the local mesh environment and recommend optimal radio configuration using on-device AI.

### Scan Engine (`DiscoveryScanEngine`)

`@MainActor @Observable` state machine with states: `idle` → `shifting` → `reconnecting` → `dwell` → `analysis` → `complete` (plus `paused` and `restoring`).

- Sends `AdminMessage setConfig.lora` to switch the connected radio to each selected preset
- Handles radio reboot + BLE reconnect automatically (60-second timeout)
- Collects packets per-preset during configurable dwell windows (default 15 min)
- 2-Packet Rule: requires ≥2 DeviceMetrics to compute Δ airtime rate
- Graceful stop: halts mid-scan, saves partial results, restores the user's home preset
- Alerts and disables scan start when primary channel uses the default key (#1706)

### Data Model (3 new SwiftData `@Model` types)

- **`DiscoverySessionEntity`** — session-level aggregates: timestamp, presets scanned, total unique nodes, average channel utilization, message/sensor counts, furthest distance, AI summary, user location, completion status
- **`DiscoveryPresetResultEntity`** — per-preset metrics: node counts (direct/mesh/infrastructure), message/sensor counts, channel utilization, airtime rate, packet success/failure rates, raw LocalStats fields (TX/RX/bad/dupe/relay/relay-canceled/online/total/uptime)
- **`DiscoveredNodeEntity`** — per-node observations: short/long name, neighbor type (direct vs. mesh), position, distance, hop count, SNR/RSSI, message/sensor counts, infrastructure flag, computed `iconName` (social → `person.2.fill`, sensor → `thermometer.medium`)

### Views

| View | Description |
|------|-------------|
| `DiscoveryScanView` | Preset multi-select (auto-filters LORA_24 for non-2.4 GHz hardware), dwell time picker, Start/Stop scan controls, live map + timer during dwell, `DiscoveryScanTip` explainer |
| `DiscoveryMapView` | MapKit with auto-zoom region fitting, color-coded annotations (green = direct 1-hop, blue = mesh/NeighborInfo), topology polylines to user position, `RadarSweepView` overlay during active scan |
| `RadarSweepView` | Animated rotating sweep + expanding pulse rings (15s rotation, 3 rings) |
| `DiscoverySummaryView` | Per-preset stat cards, RF health section (packet success/failure), FoundationModels AI recommendation (iOS 26+; fallback to structured table), PDF export |
| `DiscoveryHistoryView` | Reverse-chronological session list with detail drill-down and swipe-to-delete |

### PDF Export (`DiscoverySummaryPDF`)

- `UIGraphicsPDFRenderer` + `MKMapSnapshotter` for map image
- `FileDocument` conformance for share sheet integration
- Includes session metadata, per-preset metrics, and map snapshot

### Integration Points

- **Navigation**: `SettingsNavigationState.localMeshDiscovery` case, `NavigationLink` in Settings view
- **Tips**: `DiscoveryScanTip` (TipKit) explains the feature on first use
- **FoundationModels**: `LanguageModelSession` (iOS 26+) generates natural-language preset recommendations; gated with `#if canImport(FoundationModels)`
- **2.4 GHz Gating**: LORA_24 preset hidden for hardware without SX1280/SX1281 support

## Why did it change?

There was no existing way to understand mesh activity across different LoRa presets in a given area. Users had to manually switch presets, wait, observe, and compare — a tedious process. This feature automates that workflow and uses on-device AI (FoundationModels, iOS 26+; no internet required) to surface which preset is optimal for a location based on node count, channel utilization, and traffic patterns.

## How is this tested?

- **`DiscoveryScanEngineTests`** (Swift Testing) — initial state, `isScanning` property, default dwell duration, state transitions
- **`DiscoveryModelTests`** (Swift Testing) — entity relationships, computed properties (icon classification based on message vs. sensor counts)
- **Manual testing**: single-preset scan with 15-minute dwell against a live radio, verified node collection, map rendering, BLE reconnect after preset change, PDF export, and session persistence across app restart

## Screenshots/Videos (when applicable)

<!-- Attach screenshots of: scan config screen, discovery map with nodes, summary report with AI recommendation -->

## Checklist

- [x] My code adheres to the project's coding and style guidelines.
- [x] I have conducted a self-review of my code.
- [x] I have commented my code, particularly in complex areas.
- [x] I have verified whether these changes require an update to existing documentation or if new documentation is needed, and created an issue in the [docs repo](http://github.com/meshtastic/meshtastic/issues) if applicable.
- [x] I have tested the change to ensure that it works as intended.
