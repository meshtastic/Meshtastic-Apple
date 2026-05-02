## What changed?

Adds **Local Mesh Discovery** (Settings → Developers) — a diagnostic tool that cycles through LoRa modem presets to audit the local RF environment and recommend optimal configuration.

- **Scan Engine** (`DiscoveryScanEngine`): State machine (Idle → Shifting → Dwell → Analysis → Complete) that sends `AdminMessage setConfig.lora` per preset, handles radio reboot + BLE reconnect, and routes incoming packets to per-preset counters. 2-Packet Rule requires ≥2 DeviceMetrics to compute Δ airtime rate.
- **Data Model** (3 new SwiftData `@Model` types): `DiscoverySessionEntity`, `DiscoveryPresetResultEntity`, `DiscoveredNodeEntity` — session aggregates, per-preset metrics with raw LocalStats, per-node observations with neighbor type/SNR/RSSI/icon classification.
- **Views**: `DiscoveryScanView` (preset multi-select, dwell picker, scan controls), `DiscoveryMapView` (MapKit auto-zoom, color-coded annotations, topology polylines, radar sweep overlay), `DiscoverySummaryView` (stat cards, RF health, FoundationModels recommendation, PDF export), `DiscoveryHistoryView` (session list with detail + delete).
- **PDF Export**: `DiscoverySummaryPDF` via `UIGraphicsPDFRenderer` + `MKMapSnapshotter`.
- **Other**: `Logger.discovery` category, NeighborInfo packet forwarding in `AccessoryManager+FromRadio`, deep link `meshtastic:///settings/localMeshDiscovery`, LORA_24 gated to 2.4 GHz-capable hardware.

## Why did it change?

No existing way to understand activity across different LoRa presets in a given area. This automates the manual preset-switching workflow and uses on-device AI (FoundationModels, iOS 26+; fallback to structured table) to recommend the optimal preset for a location.

## How is this tested?

- `DiscoveryScanEngineTests` — state machine transitions, dwell timer, reconnect logic
- `DiscoveryModelTests` — entity relationships, computed properties (icon classification)
- `DiscoverySnapshotTests` — SwiftUI view rendering via `renderImage` helper
- Manual: single-preset scan with 15 min dwell against live radio, verified node collection and map rendering

## Screenshots/Videos (when applicable)

<!-- TODO: attach screenshots of scan config, discovery map, and summary report -->

## Checklist

- [x] My code adheres to the project's coding and style guidelines.
- [x] I have conducted a self-review of my code.
- [x] I have commented my code, particularly in complex areas.
- [x] I have verified whether these changes require an update to existing documentation or if new documentation is needed, and created an issue in the [docs repo](http://github.com/meshtastic/meshtastic/issues) if applicable.
- [x] I have tested the change to ensure that it works as intended.
