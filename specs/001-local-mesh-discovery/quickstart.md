# Quickstart: Local Mesh Discovery

## Prerequisites

- Xcode (latest release)
- iOS 17+ Simulator or device
- Branch: `001-local-mesh-discovery`
- `scripts/setup-hooks.sh` has been run

## Build & Run

```bash
cd /Users/garthvanderhouwen/Source/Meshtastic-Apple
open Meshtastic.xcworkspace
# Select scheme: Meshtastic, target: iPhone simulator or device
# ⌘R to build and run
```

## Access the Feature

1. Launch the app (DEBUG build)
2. Connect to a Meshtastic radio via BLE
3. Navigate to **Settings** tab
4. Scroll to **Developers** section
5. Tap **Local Mesh Discovery**

Or use the deep link:
```
meshtastic:///settings/localMeshDiscovery
```

## Run a Scan

1. Select 2+ modem presets from the picker
2. Set dwell time per preset (15 min–3 hours, in 15 min increments)
3. Tap **Start Scan**
4. The app changes the radio's LoRa preset and begins collecting packets
5. Watch the Discovery Map for nodes appearing in real-time
6. After all presets complete, review the Summary and AI Recommendation

## Run Tests

```bash
xcodebuild test \
  -workspace Meshtastic.xcworkspace \
  -scheme Meshtastic \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
  -only-testing:MeshtasticTests/DiscoveryScanEngineTests \
  -only-testing:MeshtasticTests/DiscoveryModelTests \
  -only-testing:MeshtasticTests/DiscoverySnapshotTests
```

## Key Files

| File | Purpose |
|------|---------|
| `Meshtastic/Services/DiscoveryScanEngine.swift` | State machine, dwell timer, packet routing |
| `Meshtastic/Model/DiscoverySessionEntity.swift` | Session aggregate model |
| `Meshtastic/Model/DiscoveryPresetResultEntity.swift` | Per-preset metrics model |
| `Meshtastic/Model/DiscoveredNodeEntity.swift` | Per-node observation model |
| `Meshtastic/Views/Settings/Discovery/DiscoveryScanView.swift` | Scan configuration + controls |
| `Meshtastic/Views/Settings/Discovery/DiscoveryMapView.swift` | MapKit discovery map |
| `Meshtastic/Views/Settings/Discovery/DiscoverySummaryView.swift` | Per-preset cards + AI |
| `Meshtastic/Views/Settings/Discovery/DiscoveryHistoryView.swift` | Session history list |

## Logging

All scan engine events use `Logger.discovery`. Filter in Console.app:
```
subsystem:MeshtasticLogger category:discovery
```
