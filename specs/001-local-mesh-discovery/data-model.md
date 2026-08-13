# Data Model: Local Mesh Discovery

## Entity Relationship Diagram

```mermaid
erDiagram
    DiscoverySessionEntity ||--o{ DiscoveryPresetResultEntity : "presetResults"
    DiscoverySessionEntity ||--o{ DiscoveredNodeEntity : "discoveredNodes"
    DiscoverySessionEntity ||--o{ DiscoveredBeaconEntity : "beacons"
    DiscoveryPresetResultEntity ||--o{ DiscoveredNodeEntity : "nodes"
    DiscoveryPresetResultEntity ||--o{ DiscoveredBeaconEntity : "beacons"

    DiscoverySessionEntity {
        Date timestamp PK
        String presetsScanned
        Int totalUniqueNodes
        Double averageChannelUtilization
        Int totalTextMessages
        Int totalSensorPackets
        Double furthestNodeDistance
        String completionStatus
        String aiSummaryText
        String homePreset
        Double userLatitude
        Double userLongitude
    }

    DiscoveryPresetResultEntity {
        String presetName PK
        Int dwellDurationSeconds
        Int uniqueNodesFound
        Int directNeighborCount
        Int meshNeighborCount
        Int messageCount
        Int sensorPacketCount
        Double averageChannelUtilization
        Double averageAirtimeRate
        Double packetSuccessRate
        Double packetFailureRate
        Double averageNoiseFloor
        Int noiseFloorSampleCount
    }

    DiscoveredNodeEntity {
        Int64 nodeNum PK
        String shortName
        String longName
        String neighborType
        Double latitude
        Double longitude
        Double distanceFromUser
        Int hopCount
        Float snr
        Int rssi
        Int messageCount
        Int sensorPacketCount
        String presetName
    }

    DiscoveredBeaconEntity {
        Int64 nodeNum
        String shortName
        String longName
        String message
        Int offerRegion
        Int offerPreset
        String offerChannelName
        Data offerChannelPSK
        Bool hasOfferChannel
        Float snr
        Int rssi
        Date timestamp
        String heardOnPresetName
    }
```

## Entity Definitions

### DiscoverySessionEntity

A single scan run capturing aggregate metrics across all presets.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `timestamp` | `Date` | `Date()` | When the scan started |
| `presetsScanned` | `String` | `""` | Comma-separated preset names (e.g., `"LongFast,MedFast"`) |
| `totalUniqueNodes` | `Int` | `0` | Deduplicated node count across all presets (by nodeNum) |
| `averageChannelUtilization` | `Double` | `0.0` | Weighted average channel utilization across presets |
| `totalTextMessages` | `Int` | `0` | Sum of text messages across all presets |
| `totalSensorPackets` | `Int` | `0` | Sum of environment telemetry packets across all presets |
| `furthestNodeDistance` | `Double` | `0.0` | Maximum distance (meters) to any discovered node |
| `completionStatus` | `String` | `"inProgress"` | One of: `"complete"`, `"stopped"`, `"interrupted"`, `"inProgress"` |
| `aiSummaryText` | `String` | `""` | Foundation Model generated summary (empty if unavailable) |
| `homePreset` | `String` | `""` | Original modem preset to restore on completion/stop |
| `userLatitude` | `Double` | `0.0` | User's position at scan start |
| `userLongitude` | `Double` | `0.0` | User's position at scan start |
| `presetResults` | `[DiscoveryPresetResultEntity]` | `[]` | Relationship: per-preset breakdowns |
| `discoveredNodes` | `[DiscoveredNodeEntity]` | `[]` | Relationship: all nodes observed |
| `beacons` | `[DiscoveredBeaconEntity]` | `[]` | Relationship: all beacons heard |

**Relationships**:
- `presetResults` → `[DiscoveryPresetResultEntity]` (cascade delete)
- `discoveredNodes` → `[DiscoveredNodeEntity]` (cascade delete)
- `beacons` → `[DiscoveredBeaconEntity]` (cascade delete)

**Identity**: Each session is unique by `timestamp`. No two sessions can start at the exact same `Date`.

**Lifecycle**: `inProgress` → `complete` | `stopped` | `interrupted`

### DiscoveryPresetResultEntity

Per-preset aggregated metrics within a session.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `presetName` | `String` | `""` | Modem preset name (e.g., `"LongFast"`) |
| `dwellDurationSeconds` | `Int` | `0` | Configured dwell time in seconds |
| `uniqueNodesFound` | `Int` | `0` | Nodes heard on this preset |
| `directNeighborCount` | `Int` | `0` | Nodes heard at 1-hop (SNR/RSSI available) |
| `meshNeighborCount` | `Int` | `0` | Nodes discovered via NeighborInfo |
| `messageCount` | `Int` | `0` | TEXT_MESSAGE_APP packets received |
| `sensorPacketCount` | `Int` | `0` | EnvironmentMetrics packets received |
| `averageChannelUtilization` | `Double` | `0.0` | Average `ch_util` from DeviceMetrics (2-packet rule) |
| `averageAirtimeRate` | `Double` | `0.0` | Average Δ `air_util_tx` / elapsed (2-packet rule) |
| `packetSuccessRate` | `Double` | `0.0` | From LocalStats: `numPacketsRx / (numPacketsRx + numRxBad)` |
| `packetFailureRate` | `Double` | `0.0` | From LocalStats: `numRxBad / (numPacketsRx + numRxBad)` |
| `averageNoiseFloor` | `Double` | `0.0` | Average noise floor (dBm) from LocalStats over the preset's dwell window; lower is a cleaner channel (FR-027) |
| `noiseFloorSampleCount` | `Int` | `0` | Number of LocalStats samples that carried a noise-floor value (0 → no data) |
| `session` | `DiscoverySessionEntity?` | `nil` | Inverse relationship |

**Relationships**:
- `session` → `DiscoverySessionEntity` (inverse of `presetResults`, nullify)
- `nodes` → `[DiscoveredNodeEntity]` (inverse of `presetResult`, nullify)
- `beacons` → `[DiscoveredBeaconEntity]` (inverse of `presetResult`, nullify)

> **Note on `presetName` for beacon targets**: for a custom-channel beacon target the scan keys results by a target label of the form `Preset · ChannelName` (rather than the bare preset name), so a public target and a custom-channel target on the same modem preset produce distinct `DiscoveryPresetResultEntity` rows and don't collide.

### DiscoveredNodeEntity

A single node observation during a scan, scoped to a preset.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `nodeNum` | `Int64` | `0` | Meshtastic node number (unique per physical device) |
| `shortName` | `String` | `""` | 4-char short name from NodeInfo |
| `longName` | `String` | `""` | Long name from NodeInfo |
| `neighborType` | `String` | `"direct"` | `"direct"` (1-hop, heard via SNR/RSSI) or `"mesh"` (via NeighborInfo) |
| `latitude` | `Double` | `0.0` | Node position latitude (0.0 if unknown) |
| `longitude` | `Double` | `0.0` | Node position longitude (0.0 if unknown) |
| `distanceFromUser` | `Double` | `0.0` | Computed distance in meters from user at scan time |
| `hopCount` | `Int` | `0` | Hop count from packet header |
| `snr` | `Float` | `0.0` | Signal-to-noise ratio (direct neighbors only) |
| `rssi` | `Int` | `0` | Received signal strength (direct neighbors only) |
| `messageCount` | `Int` | `0` | TEXT_MESSAGE_APP packets from this node |
| `sensorPacketCount` | `Int` | `0` | EnvironmentMetrics packets from this node |
| `presetName` | `String` | `""` | The scan target label active when observed — a preset name, or `Preset · ChannelName` for a custom-channel beacon target |
| `session` | `DiscoverySessionEntity?` | `nil` | Inverse relationship |
| `presetResult` | `DiscoveryPresetResultEntity?` | `nil` | Inverse relationship |

**Relationships**:
- `session` → `DiscoverySessionEntity` (inverse of `discoveredNodes`, nullify)
- `presetResult` → `DiscoveryPresetResultEntity` (inverse of `nodes`, nullify)

**Icon Classification** (computed, not stored): `messageCount >= sensorPacketCount` → `person.2.fill` (social); otherwise → `thermometer.medium` (sensor).

### DiscoveredBeaconEntity

A `MESH_BEACON_APP` beacon heard during a scan, advertising a mesh to discover or join.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `nodeNum` | `Int64` | `0` | Sender's Meshtastic node number |
| `shortName` | `String` | `""` | Sender short name (from NodeInfo, if known) |
| `longName` | `String` | `""` | Sender long name (from NodeInfo, if known) |
| `message` | `String` | `""` | Human-readable beacon text (`MeshBeacon.message`) |
| `offerRegion` | `Int` | `0` | Advertised region raw value; `0` = unset / not offered |
| `offerPreset` | `Int` | `-1` | Advertised modem preset raw value; `-1` = none (0 is a valid preset, so nil ≠ 0) |
| `offerChannelName` | `String` | `""` | Advertised channel name, when a custom channel is offered |
| `offerChannelPSK` | `Data` | `Data()` | Advertised channel PSK (broadcast in the beacon; needed to tune/join) |
| `hasOfferChannel` | `Bool` | `false` | Whether the beacon advertised a (non-empty-named) channel |
| `snr` | `Float` | `0.0` | Signal-to-noise ratio of the beacon packet |
| `rssi` | `Int` | `0` | Received signal strength of the beacon packet |
| `timestamp` | `Date` | `Date()` | When the beacon was received |
| `heardOnPresetName` | `String` | `""` | The scan target label the radio was dwelling on when heard |
| `session` | `DiscoverySessionEntity?` | `nil` | Inverse relationship |
| `presetResult` | `DiscoveryPresetResultEntity?` | `nil` | Inverse relationship |

**Relationships**:
- `session` → `DiscoverySessionEntity` (inverse of `beacons`, cascade)
- `presetResult` → `DiscoveryPresetResultEntity` (inverse of `beacons`, nullify)

**Computed (not stored)**: `offeredPreset` (`ModemPresets?`, nil when `offerPreset < 0`), `offeredRegion` (`RegionCodes?`, nil when `offerRegion == 0`), `displayName` (long → short → hex id).

## Validation Rules

1. `completionStatus` MUST be one of `"complete"`, `"stopped"`, `"interrupted"`, `"inProgress"`.
2. `neighborType` MUST be one of `"direct"`, `"mesh"`.
3. `dwellDurationSeconds` MUST be between 900 (15 min) and 10800 (180 min), in increments of 900.
4. `totalUniqueNodes` is computed by deduplicating `discoveredNodes` by `nodeNum` across all presets.
5. `presetsScanned` stores preset names as comma-separated for display; the authoritative preset list is in `presetResults`.
6. `DiscoveredBeaconEntity.offerPreset` uses `-1` (not `0`) as the "no preset offered" sentinel, because `0` is a valid preset (LongFast); `offerRegion` uses `0` for "unset" (matching `RegionCodes.unset`).

## State Transitions

```
DiscoverySessionEntity.completionStatus:
  "inProgress" → "complete"    (all presets dwelled, analysis done)
  "inProgress" → "stopped"     (user tapped Stop Scan)
  "inProgress" → "interrupted" (app terminated / BLE timeout)
```

## Registration

Add to `MeshtasticSchema.allModels` (schema V1 is unreleased, so new entities are added directly to V1 — no migration stage required):
```swift
DiscoverySessionEntity.self,
DiscoveryPresetResultEntity.self,
DiscoveredNodeEntity.self,
DiscoveredBeaconEntity.self,
```
