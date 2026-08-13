# Contracts — Mesh Beacons (unbuilt work)

This is a SwiftUI app, so the "interfaces" are the admin-message round-trips to the radio and the pure helper/decision functions the UI depends on. Each contract lists inputs, outputs, preconditions, and the tests that must cover it.

## C1 — Read `MeshBeaconConfig`
- **Source**: connected node's `ModuleConfig.meshBeacon` (arrives via the normal config sync in `AccessoryManager+FromRadio`).
- **Output**: populate the editor's transient buffer (flags, message, offered channel/region/preset, TX targets, interval).
- **Precondition**: radio connected and 2.8+. If absent (older firmware), the editor is unavailable / shows an unsupported state.

## C2 — Write `MeshBeaconConfig`  (FR-009–014)
- **Call**: `AccessoryManager` admin write → `AdminMessage.setModuleConfig(.meshBeacon(config))`.
- **Input**: edited `ModuleConfig.MeshBeaconConfig`.
- **Preconditions (client-validated, block on fail)**: `broadcast_message` ≤ 100 UTF-8 bytes; `broadcast_interval_secs` ≥ 3600; other `flags` bits preserved; `BroadcastTarget.channel_index` references an existing channel.
- **Output**: success → confirmation; failure → surfaced error, buffer retained.
- **Tests**: `MeshBeaconConfigEditorTests` — message-length boundary (100/101 bytes), interval boundary (3599/3600), flag-bit preservation, target validation.

## C3 — Add channel to a free secondary slot  (FR-016)
- **Call**: `AccessoryManager` `saveChannel` (`setChannel` admin) with the offered name+PSK at the lowest free secondary index (1–7), role `.secondary`. **No** LoRa-config write ⇒ **no reboot**.
- **Preconditions**: `BeaconJoinOption == .add` (see C6); connected radio.
- **No free slot**: present a replace-a-secondary picker (never primary); cancel = no-op (D2).
- **Output**: channel added; user now decodes both meshes. Failure surfaced.
- **Tests**: `BeaconAddVsSwitchTests` — picks lowest free slot; never touches primary; no-free-slot path; no LoRa write emitted.

## C4 — Switch to this channel  (FR-006, existing + D3 rollback)
- **Call**: existing `joinBeaconMesh` = `saveChannel`(primary ← offered) then `saveLoRaConfig`(region/preset, `channelNum=0`). Reboots.
- **Add (D3)**: snapshot primary before the first write; if the channel write succeeds but the LoRa apply fails, roll the primary back and surface the error.
- **Tests**: rollback path restores the snapshot on simulated LoRa-apply failure; success path unchanged.

## C5 — `frequencySlot(channelName:preset:region:) -> Int`  (FR-017)
- **Pure function** (extend `ModemPresets`/`LoraConfigEnums.swift`). Mirrors firmware: region+preset bandwidth → number of channels; `slot = (nameHash(channelName) % numChannels) + 1` for `channel_num == 0`.
- **Input**: channel name (`String`), `ModemPresets`, `RegionCodes`. **Output**: 1-based slot `Int`.
- **Invariants**: deterministic; same inputs → same slot; matches firmware for known vectors.
- **Tests**: `ModemPresetFrequencySlotTests` — assert against captured firmware vectors (e.g. default "LongFast" US slot); different names on the same preset/region yield different slots; same name → same slot.

## C6 — `beaconJoinOption(for:beacon:currentConfig:) -> BeaconJoinOption`  (FR-016)
- **Pure decision** from a beacon + the radio's current primary channel/preset/region.
- **Rules**: `.none` if no offered channel or no radio; `.add` if offered preset+region match current AND `frequencySlot(offered) == frequencySlot(currentPrimary)`; else `.switchOnly`.
- **Output drives the card**: `.add` → show **Add channel** + **Switch**; `.switchOnly` → **Switch** only; `.none` → no join action.
- **Tests**: `BeaconAddVsSwitchTests` — same-slot ⇒ `.add`; different slot / preset / region ⇒ `.switchOnly`; no channel or disconnected ⇒ `.none`.

## C7 — Passive listen ingest  (FR-015)
- **Hook**: when `FLAG_LISTEN_ENABLED` and no active scan, the `.meshBeaconApp` path persists a session-less `DiscoveredBeacon` (session/presetResult nil) instead of only logging.
- **Output**: appears in the passive Beacons list and feeds scan-setup preset/channel rows (FR-004/FR-007). Self-beacons ignored (FR-002).
- **Tests**: session-less row created outside a scan; dedup vs. existing; excluded self-beacon.
