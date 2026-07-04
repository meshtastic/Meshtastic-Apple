# Research: Mesh Beacons — cross-platform / protobuf parity

**Feature**: `014-mesh-beacons`
**Date**: 2026-07-04
**Method**: Read of the local regenerated protobufs and app source, plus web research against `github.com/meshtastic/protobufs`, `github.com/meshtastic/Meshtastic-Android`, and `meshtastic.org`. Network was reachable; findings below note which were confirmed vs. uncertain.

## Summary

The mesh-beacon wire protocol is **fully upstream** in `meshtastic/protobufs` and regenerated into this repo's `MeshtasticProtobufs`. The Apple app implements the **receive/discovery** half completely (as part of Local Mesh Discovery) but has **no** implementation of the **transmit/config** half (`ModuleConfig.MeshBeaconConfig`). There is therefore no *Android UI* to mirror — the parity gap is against the **protobuf/firmware capability**, not against an existing Android beacon screen. As of this research, `Meshtastic-Android` had no code referencing `MeshBeacon` at all.

## What exists upstream (confirmed)

Confirmed by fetching raw files from `raw.githubusercontent.com/meshtastic/protobufs/master`:

- **`meshtastic/mesh_beacon.proto`** — `MeshBeacon` message: `message` (string, ≤100 bytes), `offer_channel` (`ChannelSettings`), `offer_region` (`Config.LoRaConfig.RegionCode`), `offer_preset` (`Config.LoRaConfig.ModemPreset`). Comment: nodes in beacon mode broadcast periodically; clients cache offers; **firmware never auto-applies** them. Matches this repo's `mesh_beacon.pb.swift` field-for-field.
- **`meshtastic/portnums.proto`** — `MESH_BEACON_APP = 37`, sits right after `NODE_STATUS_APP = 36`. Comment: "Periodically broadcast by nodes in beacon mode; received by nodes with `MeshBeaconConfig.FLAG_LISTEN_ENABLED`." Matches this repo's `portnums.pb.swift`.
- **`meshtastic/module_config.proto`** — `ModuleConfig.MeshBeaconConfig` with the full field set below, including the `Flags` enum and the `BroadcastTarget` nested message. Matches this repo's `module_config.pb.swift` / `localonly.pb.swift`.

Minor discrepancy: the web fetch reported `mesh_beacon` as oneof field **17** in `ModuleConfig.payload_variant`, whereas this repo's generated Swift decodes it at field **18**. This is almost certainly web-fetch imprecision (the field set is otherwise identical) and is not load-bearing for the spec; the generated bindings in the repo are authoritative for the client.

## MeshBeaconConfig field reference (the PROPOSED transmit surface)

From `module_config.pb.swift` (`ModuleConfig.MeshBeaconConfig`), matching upstream:

| Field | Type | Notes |
|---|---|---|
| `flags` | `UInt32` | Bitwise-OR of `Flags`. |
| `broadcast_send_as_node` | `UInt32` | Spoof the `from` of outgoing beacons as this node ID; 0 = local node. Remote admin may only set to their own ID. |
| `broadcast_message` | `String` | Text in each beacon. Firmware enforces ≤100 bytes. |
| `broadcast_offer_channel` | `ChannelSettings` | Channel (name + PSK) advertised in `offer_channel`. |
| `broadcast_offer_region` | `RegionCode` | Advertised in `offer_region`. |
| `broadcast_offer_preset` | optional `ModemPreset` | Advertised in `offer_preset`. |
| `broadcast_on_channel` | `ChannelSettings` | Single-target TX channel (name + PSK). If unset, TX on primary. Used only when `broadcast_targets` is empty. |
| `broadcast_on_region` | `RegionCode` | Region for single-target TX. |
| `broadcast_on_preset` | optional `ModemPreset` | Preset for TX; radio temporarily switches to it for TX if different. |
| `broadcast_interval_secs` | `UInt32` | How often to broadcast. **Min 3600 (1 h), default 3600.** |
| `broadcast_targets` | repeated `BroadcastTarget` | Multi-target TX list; when non-empty, one beacon per entry, each temporarily switching the radio. When empty, the scalar single-target fields are used. |

`Flags` enum: `FLAG_NONE = 0`, `FLAG_LISTEN_ENABLED = 1`, `FLAG_BROADCAST_ENABLED = 2`, `FLAG_LEGACY_SPLIT = 4` (split combined beacon into separate `MESH_BEACON_APP` + `TEXT_MESSAGE_APP` for text-only-decoding firmware).

`BroadcastTarget`: `preset` (optional `ModemPreset`, falls back to running config), `region` (`RegionCode`, UNSET = running config), `channel_index` (optional `UInt32`, index into the node's channel table — the referenced channel must already exist so its key is available). Note the two TX-channel representations: the single-target path embeds `ChannelSettings` inline (`broadcast_on_channel`), whereas a `BroadcastTarget` references a channel-table slot by index — described upstream as equal, first-class options.

Firmware listen behavior worth mirroring: the `FLAG_LISTEN_ENABLED` comment states the **text portion is delivered to the local message inbox** and offered channel/preset are cached for the client. The Apple app currently routes beacons to the discovery engine only during a scan and otherwise logs them — it does not deliver beacon text to the inbox. This informs the passive-listen open question (spec FR-015).

## What the Apple app implements today (receive side)

- `AccessoryManager.swift` `.meshBeaconApp` case: decodes `MeshBeacon` and, only when a scan is active, calls `DiscoveryScanEngine.handleBeacon(_:packet:)`; otherwise logs.
- `DiscoveryScanEngine.handleBeacon` / `autoQueueBeacon`: stores `DiscoveredBeaconEntity`, skips self-beacons, auto-queues public-channel presets, queues custom-channel targets, dedupes by target identity.
- `applyChannel(for:)`: tunes the primary channel to a custom-channel beacon's name + PSK during its dwell and reverts afterward; snapshot/restore of the real primary channel.
- `DiscoveredBeaconEntity`, `DiscoverySessionEntity` (cascade `beacons`), `DiscoveryPresetResultEntity` (nullify `beacons`): the SwiftData model.
- `DiscoveryScanView`: `beaconPresets` pre-selection (union-only, once) + beacon-icon row flag + explanatory footer.
- `DiscoverySummaryView`: Beacons section, per-beacon cards with offered chips + SNR, and the Switch to this channel action (via `AccessoryManager+ToRadio.joinBeaconMesh`).

## What is NOT implemented (the parity gap → PROPOSED)

- No read or write of `ModuleConfig.MeshBeaconConfig` anywhere in `Meshtastic/` (only the receive-side `MeshBeacon` message is consumed). Confirmed by grep: the only non-generated references to beacon config symbols are in `AccessoryManager.swift` (the receive `case`) and the docs.
- No UI to enable listening/broadcasting, set the beacon message, choose offered channel/region/preset, choose TX radio settings, or set the interval.
- No delivery of passively-heard beacon text to the message inbox (firmware's stated listen behavior).

## Cross-platform parity notes

- **Android**: `Meshtastic-Android` code search for `MeshBeacon` returned **0 results** at the time of research — no beacon config UI or receive handling to mirror. The transmit/config side is greenfield on Apple *and* Android; the Apple receive/discovery integration appears to be ahead of Android.
- **Firmware**: "beacon mode" traces to a community module (`jkpg-mesh/mesh-beacon-Module`) whose protocol has been upstreamed into `meshtastic/protobufs`. Whether the *official* firmware ships a first-class beacon module (vs. the community module) was not definitively confirmed from public docs during this research — treat firmware availability/behavior specifics as an implementation-time verification item.

## Open questions carried into the spec

1. **Navigation home** for the beacon config editor (Module Configuration list and/or a deep link). *(FR-013)*
2. **Message-length UX**: block save vs. live truncate at 100 bytes. *(FR-015)*
3. **Interval UX**: clamp vs. reject below 3600 s; which interval presets to offer. *(FR-017)*
4. **Multi-target scope**: does v1 read/preserve/edit `broadcast_targets` and `broadcast_send_as_node`, or only the single-target scalar path? *(FR-018)*
5. **`FLAG_LEGACY_SPLIT`**: expose to users or manage automatically. *(FR-019)*
6. **Passive listen**: capture beacons outside a scan? Deliver text to the inbox (per firmware), a dedicated Beacons list, or both? Persistence when there is no `DiscoverySession`? Join-outside-scan in scope? *(FR-015)*
7. **Named channel with empty/default PSK** in a received beacon — treat as default key or reject as not joinable? *(edge case)*
8. **Join rollback** — if a Switch-to-this-channel join partially applies then fails, roll back the primary-channel change? *(edge case)*

## Sources

- [meshtastic/protobufs — mesh_beacon.proto](https://github.com/meshtastic/protobufs/blob/master/meshtastic/mesh_beacon.proto)
- [meshtastic/protobufs — module_config.proto](https://github.com/meshtastic/protobufs/blob/master/meshtastic/module_config.proto)
- [meshtastic/protobufs — portnums.proto](https://github.com/meshtastic/protobufs/blob/master/meshtastic/portnums.proto)
- [meshtastic/Meshtastic-Android](https://github.com/meshtastic/Meshtastic-Android)
- [jkpg-mesh/mesh-beacon-Module (community firmware module)](https://github.com/jkpg-mesh/mesh-beacon-Module)

---

# Phase 0 Decisions (plan)

The parity findings above are the input; this section is the plan's decision log. Several of the "open questions carried into the spec" were resolved in the spec's `## Clarifications` (Session 2026-07-04): message-length → block-with-error, interval → block-below-3600, multi-target → full (targets + send-as-node), `FLAG_LEGACY_SPLIT` → manage automatically, passive-listen → session-less `DiscoveredBeacon` + Beacons list, editor home → Settings → Module Configuration. The remaining decisions:

## D1 — Frequency-slot derivation (FR-017)

**Decision**: Add a pure helper (extend `ModemPresets` in `LoraConfigEnums.swift`) computing a channel's operating slot from `(channelName, modemPreset, region)` as firmware does — region+preset bandwidth → number of channels, then `slot = (nameHash(channelName) % numChannels) + 1` for `channel_num == 0`. Compare the beacon channel's slot to the connected radio's current primary slot; **Add** is offered only on a match.
**Rationale**: Adding a secondary channel never retunes (frequency derives from the *primary* name), so Add only works when the offered mesh is already on the current frequency. Slot derivation is the only correct gate — "same preset" is insufficient.
**Alternatives**: preset+region-only gate (would offer Add for meshes the radio can't hear); ask firmware (no such round-trip; value is deterministic). Validate against firmware vectors in `ModemPresetFrequencySlotTests`.

## D2 — No free secondary slot (FR-017 clarification)

**Decision**: When slots 1–7 are all occupied, **Add** presents a picker to replace an existing *secondary* channel (never the primary); cancel = no change.
**Rationale**: Rejecting is a dead end; replacing matches intent; protecting the primary avoids self-eviction. **Alternatives**: reject-with-message; auto-evict oldest (surprising).

## D3 — Switch partial-failure rollback (edge case / open Q8)

**Decision**: Snapshot the primary channel before `joinBeaconMesh` mutates it; if the channel write succeeds but the region/preset apply fails, roll the primary channel back and surface the error.
**Rationale**: A new channel on the old preset/region strands the radio on an undecodable frequency; both-or-neither is least surprising. Safe because the channel write does not reboot. **Alternatives**: leave-partial+warn; no rollback (current gap).

## D5 — Named channel with empty PSK (edge case / open Q7)

**Decision**: Treat an offered channel name with empty PSK as the default/public key (as firmware does) and label it "open channel"; do not reject.
**Rationale**: Empty-PSK is a valid Meshtastic channel; rejecting drops legitimate open meshes.

## D7 — MeshBeaconConfig editor mechanics (FR-009–014)

**Decision**: New SwiftUI screen `Views/Settings/Config/Module/MeshBeaconConfig.swift` in the Module Configuration list; reads `ModuleConfig.MeshBeaconConfig`, writes via `AdminMessage` `setModuleConfig.meshBeacon` through `AccessoryManager`; blocking client-side validation (message ≤ 100 bytes, interval ≥ 3600 s) with inline errors; full multi-target support. Mirrors existing module-config screens.
**Rationale**: Consistency (Constitution I/III) and matches the clarify decisions.

## Technical unknowns

All standard for this repo (SwiftUI/SwiftData/protobuf/Swift Testing, iOS·iPadOS·macOS) — no NEEDS CLARIFICATION. One process gate: fetch the canonical Meshtastic Client Design Standards before building the config-editor UI (Constitution VIII).
