# Phase 1 Data Model — Mesh Beacons

The receive side already has its SwiftData model. The unbuilt work adds **no new persisted entity** — it reuses `DiscoveredBeaconEntity`, edits radio config (not stored locally), and introduces two in-memory value types.

## Persisted (SwiftData) — existing, reused

### `DiscoveredBeaconEntity` (no schema change)
A beacon heard from another node. Already defined; both relationships are **optional**, which is what enables session-less passive beacons (FR-015).
- `nodeNum: Int64`, `shortName: String`, `longName: String`, `message: String`
- `offerRegion: Int` (0 = unset), `offerPreset: Int` (−1 = none, 0 = LongFast), `offerChannelName: String`, `offerChannelPSK: Data`, `hasOfferChannel: Bool`
- `snr: Float`, `rssi: Int`, `timestamp: Date`, `heardOnPresetName: String`
- `session: DiscoverySessionEntity?` (cascade) — **nil for a passively-heard beacon**
- `presetResult: DiscoveryPresetResultEntity?` (nullify) — **nil for a passively-heard beacon**
- Computed: `offeredPreset: ModemPresets?`, `offeredRegion: RegionCodes?`, `displayName: String`

**Change for FR-015**: passive-listen writes rows with `session`/`presetResult` = nil. A passive Beacons list queries `DiscoveredBeaconEntity` where `session == nil` (or all, grouped). Retention = explicit user deletion (matches sessions).

`DiscoverySessionEntity` / `DiscoveryPresetResultEntity` — unchanged; owned by spec 001.

## Radio configuration (not persisted locally)

### `ModuleConfig.MeshBeaconConfig` (generated protobuf; edited via admin message)
The transmit/config surface (FR-009–014). Read from the connected node's config, edited in a transient buffer, written back via `AdminMessage`. Field reference in [research.md](./research.md). Client-enforced validation:
- `broadcast_message`: ≤ 100 UTF-8 bytes — **block save** with inline error if exceeded (FR-011).
- `broadcast_interval_secs`: ≥ 3600 (default 3600) — **block save** if below (FR-013).
- `flags`: bitfield; UI toggles `FLAG_LISTEN_ENABLED` / `FLAG_BROADCAST_ENABLED`, **preserving** other bits (`FLAG_LEGACY_SPLIT` managed automatically — D4).
- Offered: `broadcast_offer_channel` / `_region` / `_preset` (all optional; a text-only beacon offers none).
- Transmit target: single-target scalars (`broadcast_on_channel/_region/_preset`) **and** repeated `broadcast_targets` + `broadcast_send_as_node` (full multi-target, FR-014). A `BroadcastTarget.channel_index` must reference an existing channel slot.

### `Channel` (generated protobuf; edited via admin message)
- **Switch** (FR-006, existing): set primary channel (index 0) to the offered name+PSK, then apply region/preset (reboot). Add rollback of the primary snapshot on partial failure (D3).
- **Add** (FR-016, new): write the offered channel into the **lowest free secondary slot** (index 1–7), role `.secondary`, leaving primary + LoRa config untouched (no reboot). If no free slot, prompt to replace a secondary (D2).

## In-memory value types (not persisted)

### `ChannelFrequencySlot` (derived — FR-017)
Pure function `frequencySlot(channelName:preset:region:) -> Int`, mirroring firmware's `channel_num` name-hash. Inputs: channel name, `ModemPresets`, `RegionCodes`. Used to compare a beacon channel's slot to the radio's current primary slot; **Add** is offered only when equal. Stateless, testable in isolation.

### `BeaconJoinOption` (derived — FR-016)
Computed per beacon card from the connected radio's current config:
- `.add` — offered preset+region match AND `frequencySlot(offered) == frequencySlot(currentPrimary)` → show **Add channel** (+ Switch).
- `.switchOnly` — any mismatch (slot/preset/region) or no free/replaceable slot handling needed → show **Switch to this channel** only.
- `.none` — beacon advertised no channel, or no radio connected → no join action (Switch already requires a channel + connection).

## Validation & state notes
- All radio writes go through `AccessoryManager` admin-message helpers (Constitution III); offers are advisory and never auto-applied (FR-008).
- Config edit buffer is discarded on cancel; only an explicit Save writes the admin message.
- Beacon config editor and both join actions require a connected radio; the passive Beacons list and scan-setup rows work offline from stored data.
