# Feature Specification: Mesh Beacons

**Feature Branch**: `014-mesh-beacons`
**Created**: 2026-07-04
**Status**: Partially Implemented (receive/discovery/join shipped; broadcast/config proposed)
**Input**: User description: "Mesh Beacons — capture `MESH_BEACON_APP` advertisements to discover, display, and join meshes (including private custom-channel meshes) while a Local Mesh Discovery scan is running, and configure the user's own node to broadcast beacons so others can find and join its mesh."

## Relationship to Local Mesh Discovery (spec 001)

Mesh Beacons is a capability that plugs into the scan engine specified in [spec 001 — Local Mesh Discovery](../001-local-mesh-discovery/spec.md). **This spec is authoritative for beacon receive/discovery, join, and (proposed) broadcast/config.** Spec 001 remains authoritative for the scan lifecycle that beacon discovery runs inside, and this spec references — but does not re-specify — the following, all owned by spec 001:

- The scan **state machine** (Idle → Shifting → Reconnecting → Dwell → Analysis → …) and the per-preset **dwell** / reboot-reconnect behavior. Beacon ingestion (FR-001) happens during the Dwell state.
- The **LoRa-config snapshot/restore** (spec 001 FR-025) and the **primary-channel snapshot/restore** to and from the default public channel (spec 001 FR-026). Custom-channel beacon targets (FR-005) extend this same snapshot/restore rather than adding a new one.
- The **`ScanTarget` queue** — the in-memory list of dwell targets the engine walks. Beacons *enqueue* targets (FR-003, FR-005, FR-007), but the queue, its ordering, and the `ScanTarget` type itself remain owned by spec 001 (`ScanTarget` already carries the optional custom-channel capability these targets use).
- The Packet Router / **Data Flow**; `MESH_BEACON_APP` is one of the packet types it routes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Discover, Display, and Join Meshes via Beacons (Priority: P1)

Some radios run in *beacon mode* and periodically broadcast a `MESH_BEACON_APP` packet advertising their mesh — a short message plus, optionally, the channel (name + PSK), region, and modem preset it runs on. While scanning, the user's radio hears these beacons and the discovery feature captures them, shows them in the results, and uses them to steer the scan: a mesh advertised on the public channel adds its preset to the scan automatically, and a mesh advertised on a **custom channel** is tuned into directly (using the key the beacon broadcast) so even a private mesh is found and measured. Custom channels heard from past beacons also appear as their own selectable rows in the scan setup (a **Beacon Channels** section), so the user can deliberately include a known private mesh in a run up front. From the results the user can tap **Switch to this channel** to join the advertised mesh.

**Why this priority**: Beacons let discovery find meshes the user didn't know to look for — including private, custom-channel meshes that the public-channel scan cannot hear — and turn "there's a mesh over there" into an actionable join. It builds on the scan engine and packet-ingestion path specified in [spec 001](../001-local-mesh-discovery/spec.md).

**Independent Test**: With a second radio beaconing a custom channel + preset, run a scan on any preset; verify the beacon appears in the Beacons section with its message and offered channel/preset/region, that a dwell tunes to the advertised channel and lists its nodes, and that **Switch to this channel** reconfigures the radio onto that mesh.

**Acceptance Scenarios**:

1. **Given** a scan is dwelling, **When** a `MESH_BEACON_APP` packet is received from another node, **Then** the app decodes the `MeshBeacon`, stores it against the session and current preset result, and shows it in the summary's Beacons section with its message, sender, offered preset/region/channel, and SNR.
2. **Given** a beacon advertises a modem preset on the **public channel** (no custom channel) that the scan has not queued or completed, **When** it is received, **Then** that preset is appended to the scan queue so the run also dwells on it.
3. **Given** a preset was previously heard in a beacon, **When** the user next opens the scan setup, **Then** that preset is pre-selected in the Modem Presets list and marked with a beacon icon.
4. **Given** a beacon advertises a **custom channel** (non-empty name + PSK), **When** it is received, **Then** a scan target carrying that channel is queued; when it dwells, the radio's primary channel is tuned to the offered name + PSK (and region/preset), so the dwell lands on that mesh's derived frequency and can decode it. Its results are labeled `Preset · ChannelName`.
5. **Given** a beacon in the results advertised a channel, **When** the user taps **Switch to this channel** and confirms, **Then** the app sets the radio's primary channel to the offered channel and applies the offered region and preset; the radio reboots and reconnects on that mesh.
6. **Given** no beacons are heard during a scan, **When** the summary renders, **Then** the Beacons section is hidden entirely.
7. **Given** a custom channel was previously heard in a beacon, **When** the user opens the scan setup, **Then** that channel appears as its own row in a **Beacon Channels** section (pre-selected, with a beacon indicator); **When** the user starts the scan with it selected, **Then** the run includes a custom-channel target that tunes to that channel from the start, even if that beacon is never re-heard during the run.
8. **[PROPOSED]** **Given** a beacon advertised a channel that runs on the connected radio's current preset, region, and frequency slot, **When** the user opens its card, **Then** an **Add channel** action is offered; confirming adds the channel to a free secondary slot with no reboot and the user can message that mesh alongside their own. **Given** the channel needs a different frequency slot, preset, or region, **Then** only **Switch to this channel** (reboot) is offered.

### User Story 2 — Broadcast a Beacon from My Own Node (Priority: P2) [PROPOSED]

The receive/discovery side above is implemented. The complementary side — configuring the user's own node to *transmit* beacons so other people's discovery scans can find and join their mesh — is specified here but not yet built. The wire protocol (`ModuleConfig.MeshBeaconConfig`, port 37) is fully present in the regenerated protobufs; only client UI/config work remains. A user turns on beacon broadcasting, sets the advertised message and (optionally) the channel/region/preset their mesh offers, and picks a broadcast interval; their node then periodically emits a `MESH_BEACON_APP` packet.

**Why this priority**: It closes the loop — discovery can only find meshes that beacon. It is additive and lower priority than the receive side, and has open UX questions (below), so it ships after the implemented discovery path.

**Independent Test**: With two radios, enable beacon broadcast on radio A with a message and an offered custom channel; run a discovery scan on radio B; verify B captures A's beacon with the advertised fields and can Switch to that channel.

**Acceptance Scenarios**:

1. **Given** a connected radio, **When** the user opens the beacon config editor, **Then** it reads the radio's `MeshBeaconConfig` and shows the current flags, message, offered channel/region/preset, and broadcast interval.
2. **Given** the editor, **When** the user enables broadcast, sets a message and interval, and saves, **Then** the app writes the config back via an `AdminMessage` and the node begins beaconing at that interval.
3. **Given** a message longer than the firmware limit, **When** the user tries to save, **Then** the app prevents it and explains the limit.

---

### Edge Cases

- **Beacon from the scanning node itself**: A beacon whose sender is the connected node is ignored (not stored, not queued).
- **Beacon advertises an already-scanned or already-queued mesh**: The target is not queued again — duplicates are suppressed by target identity (preset + region + channel), so a repeatedly-broadcast beacon adds its mesh to the scan at most once.
- **Beacon offers a preset but no channel**: Treated as a public-channel target — the preset is scanned on the default public channel (no channel switch).
- **Beacon advertises a custom channel followed by a public/manual target**: After a custom-channel dwell, the scan reverts the primary channel to the default public channel before the next public target so it hears the public mesh again.
- **Beacon offers a named channel with an empty or default PSK**: Treat it as the default/public key (joinable) and label it "open channel"; do not reject the offer (research D5).
- **Switch to this channel partially applies then fails**: The primary channel is snapshotted before the join; if the channel write succeeds but the subsequent LoRa/region/preset apply fails, the primary-channel change is rolled back and the error is surfaced (research D3).

## Requirements *(mandatory)*

### Functional Requirements — Beacon Receive & Discovery (Implemented)

- **FR-001** [IMPLEMENTED]: During each dwell window the system MUST ingest `MESH_BEACON_APP` packets, decode the `MeshBeacon` payload (message, optional offered channel [name + PSK], optional offered region, optional offered modem preset), and persist each as a `DiscoveredBeacon` associated with the session and the active preset result. Beacons from the connected (scanning) node itself MUST be ignored.
- **FR-002** [IMPLEMENTED]: The system MUST display received beacons in the scan summary in a Beacons section showing each beacon's message, sender, offered preset/region/channel (as applicable), and signal strength (SNR). The section MUST be hidden when no beacons were received.
- **FR-003** [IMPLEMENTED]: When a beacon advertises a modem preset on the **public channel** (no custom channel) that is neither the active target, already queued, nor already completed this session, the system MUST append that preset to the scan queue so the run also dwells on it, and reflect it in the user-visible preset selection.
- **FR-004** [IMPLEMENTED]: In the scan setup, the system MUST pre-select (once, non-destructively) any modem preset for which a beacon has previously been recorded, and flag such presets with a beacon indicator so the user understands why they are selected.
- **FR-005** [IMPLEMENTED]: When a beacon advertises a **custom channel** (non-empty name + PSK), the system MUST queue a scan target that carries that channel, and when the target dwells MUST tune the radio's primary channel to the offered name + PSK (and apply any offered region) before the preset change, so the dwell lands on that mesh's derived frequency and can decode it. The scan MUST snapshot the user's real primary channel the first time it tunes away and restore it when the scan finishes or is stopped (extending spec 001 FR-026). Discovered nodes and the preset result for such a target MUST be keyed by a label that includes the channel (e.g. `Preset · ChannelName`) so a public target and a custom-channel target on the same preset do not collide, and after a custom-channel dwell the system MUST revert to the default public channel before the next public/manual target. The well-tested public-channel scan path MUST be unchanged when no custom-channel beacons are present.
- **FR-006** [IMPLEMENTED]: The system MUST provide a **Switch to this channel** action on beacons that advertised a channel. On confirmation it MUST set the radio's primary channel to the offered channel (name + PSK) and apply the offered region and modem preset (with `channelNum = 0` so the frequency derives from the new channel), carrying the radio's other existing LoRa fields through so they are not wiped. This reboots the radio onto the advertised mesh. Failures MUST be surfaced to the user.
- **FR-007** [IMPLEMENTED]: In the scan setup the system MUST render each distinct custom channel a beacon has advertised (deduped by channel name + preset) as its own selectable row in a **Beacon Channels** section, separate from the Modem Presets rows, showing the channel name, the preset it runs on, and a beacon indicator. Selecting a channel MUST include a custom-channel scan target (carrying the channel name + PSK and any offered region) in the run from the start — not only when that beacon is re-heard mid-scan (extends FR-005). These rows MUST be pre-selected once per appearance (union-only, never clearing the user's choices), a scan MAY consist solely of beacon-channel targets with no modem preset selected, and the section MUST be hidden when no custom-channel beacons have been recorded.
- **FR-008** [IMPLEMENTED]: The client MUST consume the upstream `MeshBeacon` and `ModuleConfig.MeshBeaconConfig` bindings from the regenerated `MeshtasticProtobufs`; it MUST NOT hand-edit generated `.pb.swift` files or define app-local wire types (Constitution §V). The client MUST treat every offered channel/region/preset in a received beacon as advisory and MUST NOT auto-apply it to the radio — radio config changes happen only via the explicit scan-steering path (FR-003, FR-005), the explicit **Switch to this channel** / **Add channel** actions (FR-006, FR-016), or the user's own beacon-config edits (FR-009–FR-015). This mirrors the firmware, which never auto-applies a beacon's offers.

### Functional Requirements — Beacon Broadcast & Config (Proposed / Future)

These cover the transmit side of beacons — configuring the user's own node to advertise its mesh — and are not yet implemented. The protobufs are present; only client work remains.

- **FR-009** [PROPOSED]: The system MUST provide a MeshBeacon module configuration editor, reached from the **Settings → Module Configuration list** alongside the other module configs, that reads the connected radio's `ModuleConfig.MeshBeaconConfig` and writes changes back via an `AdminMessage` (`setModuleConfig.meshBeacon`).
- **FR-010** [PROPOSED]: The editor MUST let the user toggle `FLAG_LISTEN_ENABLED` (receive/act on inbound beacons) and `FLAG_BROADCAST_ENABLED` (periodically transmit beacons) via the `flags` bitfield, preserving any other bits already set.
- **FR-011** [PROPOSED]: The editor MUST let the user edit the beacon `broadcast_message` and MUST block saving a message longer than the firmware-enforced 100 bytes, showing an inline error with the limit rather than silently truncating the user's text.
- **FR-012** [PROPOSED]: The editor MUST let the user set what the beacon offers to listeners: `broadcast_offer_channel` (name + PSK), `broadcast_offer_region`, and `broadcast_offer_preset`. A beacon MAY offer none of these (text-only beacon).
- **FR-013** [PROPOSED]: The editor MUST let the user set `broadcast_interval_secs` (default 3600) and MUST block saving a value below the firmware minimum of 3600 s, showing an inline error with the limit rather than silently clamping.
- **FR-014** [PROPOSED]: The editor MUST let the user set the radio settings a beacon is transmitted on. v1 MUST support the full multi-target model: the single-target scalar fields (`broadcast_on_channel`, `broadcast_on_region`, `broadcast_on_preset`) **and** the repeated `broadcast_targets` list plus `broadcast_send_as_node`, reading, editing, and preserving all of them. `FLAG_LEGACY_SPLIT` (which splits a combined beacon into separate `MESH_BEACON_APP` + `TEXT_MESSAGE_APP` packets for text-only-decoding firmware) is managed automatically — it is not exposed as a user toggle, and its existing bit MUST be preserved when writing other flags (research D4).
- **FR-015** [PROPOSED]: When listening is enabled and a beacon arrives outside an active scan, the system MUST persist it as a session-less `DiscoveredBeacon` (no `DiscoverySession` owner) and surface it in a reviewable Beacons list. These passively-captured beacons MUST also feed the scan-setup beacon-preset rows (FR-004) and Beacon Channels rows (FR-007), so a user can include a beaconed mesh in a scan without having first run one. Retention follows the same explicit-user-deletion model as sessions. (The current build only logs such packets; FR-001 stores beacons only during a dwell.)

### Functional Requirements — Beacon Join Enhancements (Proposed / Future)

- **FR-016** [PROPOSED]: On a beacon that advertised a channel, in addition to **Switch to this channel** (FR-006) the system MUST offer an **Add channel** action whenever joining that mesh requires **no retune and no reboot** — i.e. the beacon's offered preset and region already match the connected radio **and** the offered channel resolves to the radio's current operating frequency slot. **Add channel** MUST add the offered channel (name + PSK) to a free secondary channel slot via a `setChannel` `AdminMessage`, leaving the primary channel and LoRa config unchanged (no reboot), so the user monitors and participates in that mesh **alongside** their own instead of leaving it. When a retune is required — a different frequency slot, preset, or region — the app MUST offer only **Switch to this channel** (retune + reboot, FR-006), never **Add**.
- **FR-017** [PROPOSED]: To decide FR-016's "same frequency slot" condition correctly, the app MUST derive a channel's operating slot from its name + modem preset + region the way the firmware does (the `channel_num` name-hash used when `channel_num == 0`), and compare the offered channel's slot to the connected radio's current slot. **Add** MUST be offered only when the slots match, so it is never shown in a case where adding a secondary channel would not actually let the user hear that mesh. When no free secondary channel slot is available, **Add** MUST present a picker to replace an existing secondary channel (never the primary); cancelling makes no change (research D2). Both **Add** and **Switch** require a connected radio.

### Key Entities

- **DiscoveredBeacon**: A `MESH_BEACON_APP` beacon heard during a session. Attributes: sender node number, short/long name, message text, offered region (raw value; 0 = unset), offered modem preset (raw value; sentinel −1 = none, since 0 is a valid preset), offered channel name and PSK plus a "has offered channel" flag, SNR, RSSI, timestamp, and the target label it was heard on. Linked to its `DiscoverySession` (cascade) and `DiscoveryPresetResult` (nullify) — both defined in [spec 001](../001-local-mesh-discovery/spec.md) — when heard during a scan; both links are optional so a beacon heard passively outside a scan (FR-015) is stored session-less. The offered PSK is broadcast in the beacon (not a local secret) and is required to tune to / join the advertised mesh.
- **MeshBeaconConfig** *(proposed transmit surface; wire type owned by `MeshtasticProtobufs`, not app-defined)*: the connected radio's beacon module config that the proposed editor (FR-009–FR-015) reads and writes. Fields: `flags` (bitfield of `FLAG_LISTEN_ENABLED` / `FLAG_BROADCAST_ENABLED` / `FLAG_LEGACY_SPLIT`), `broadcast_message`, `broadcast_offer_channel` / `broadcast_offer_region` / `broadcast_offer_preset` (what the beacon advertises), the single-target TX scalars `broadcast_on_channel` / `broadcast_on_region` / `broadcast_on_preset`, the repeated `broadcast_targets` list, `broadcast_send_as_node`, and `broadcast_interval_secs`. See [research.md](./research.md) for the full field reference.

> Note: `ScanTarget` (the in-memory dwell target that carries the optional custom channel) is owned by [spec 001](../001-local-mesh-discovery/spec.md) — beacon targets populate it but this spec does not define it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When a node within range is beaconing, its beacon appears in the summary's Beacons section — with its message and any offered channel/preset/region — within a single dwell window of it being heard.
- **SC-002**: A mesh advertised only on a custom channel (one the public-channel scan cannot decode) is discovered and its nodes are listed after the custom-channel dwell — a mesh the bare public-channel scan cannot hear.
- **SC-003**: From a beacon that advertised a channel, a user joins that mesh via **Switch to this channel** in one confirmation step, and the radio reboots and reconnects on the advertised mesh.
- **SC-004**: A custom channel heard in a past beacon appears as a selectable **Beacon Channels** row in the next scan setup and can be included in a run from the start without the beacon being re-heard.
- **SC-005**: A scan with no beacons present produces the same results as the pre-beacon public-channel scan path — enabling beacon discovery never regresses the existing scan.
- **SC-006** [PROPOSED]: With beacon broadcast enabled on one radio, a second radio running discovery captures that beacon with all advertised fields (message, offered channel/region/preset) intact.
- **SC-007** [PROPOSED]: For a beacon whose channel already runs on the radio's current preset/region/frequency, the user joins it via **Add channel** in one confirmation step with **no reboot**, keeps their existing primary channel, and can message both meshes; for a beacon needing a retune, only **Switch to this channel** is offered.

## Clarifications

### Session 2026-07-03

- Q: What are mesh beacons and how does discovery use them? → A: `MESH_BEACON_APP` packets advertise a mesh (message + optional channel/region/preset). During a scan they are captured as `DiscoveredBeacon` records and shown in a Beacons section; the meshes they advertise are added to the scan (FR-001–FR-003).
- Q: Can discovery scan a mesh on a custom channel (custom name/PSK), not just a preset? → A: Yes. A beacon's custom channel changes both the derived frequency (from the channel name) and the encryption (its PSK), so scanning the bare preset on the public channel can't hear it. The scan queue is generalized to scan targets that can carry a channel; a custom-channel target tunes the radio to the offered name + PSK during its dwell and reverts to the public channel afterward. The public-channel scan path is unchanged when no such beacons are present (FR-005).
- Q: How does a beacon-advertised preset get selected? → A: A public-channel beacon's preset is appended to the running scan queue and pre-selected (with a beacon icon) in the next scan setup (FR-003, FR-004).
- Q: Can the user join a beaconed mesh? → A: Yes — a **Switch to this channel** action on a beacon that advertised a channel sets the primary channel to the offered channel and applies its region/preset, rebooting onto that mesh (FR-006).

### Session 2026-07-04

- Q: When a beacon arrives outside an active scan (listening enabled), what happens? → A: Persist it as a session-less `DiscoveredBeacon` and surface it in a reviewable Beacons list; these also feed the scan-setup Beacon Channels / preset rows so a mesh can be scanned without first running a scan (FR-015).
- Q: For the proposed beacon config editor, single-target or multi-target in v1? → A: Full multi-target — read/edit/preserve the repeated `broadcast_targets` list and `broadcast_send_as_node`, not just the single-target scalars (FR-014).
- Q: Where does the beacon (`MeshBeaconConfig`) editor live? → A: In the Settings → Module Configuration list, alongside the other module configs (FR-009).
- Q: How are out-of-range beacon config values handled (message > 100 bytes, interval < 3600 s)? → A: Block save with an inline error showing the limit; never silently truncate or clamp the user's input (FR-011, FR-013).

## Assumptions

- Beacon support consumes the `MeshBeacon` message (`MESH_BEACON_APP`, port 37) from the `mesh_beacon.proto` bindings, which were added upstream and regenerated into `MeshtasticProtobufs`. The implemented receive side only reads beacons (it does not transmit them); the proposed broadcast side (FR-009–FR-015) additionally reads and writes `ModuleConfig.MeshBeaconConfig`. No app-defined protobuf types are added.
- `MESH_BEACON_APP` packets are decoded and, while a scan is active, routed to the discovery engine; outside a scan they are logged only (until passive listen, FR-015, is built). A beacon's offered channel/region/preset is advisory — the firmware never auto-applies it; the client stores it and acts on it only via the scan queue or the explicit Switch to this channel action.
- The existing `saveChannel` method (a `setChannel` `AdminMessage`) is used to tune the primary channel to a beacon's advertised channel — for a custom-channel scan target (FR-005) and for **Switch to this channel** (FR-006). The `joinBeaconMesh` method composes `saveChannel` + `saveLoRaConfig` for the join action. (Spec 001 owns the `saveLoRaConfig` / `saveChannel` usage for the public-channel scan path and the home-config restore.)
- Beacon-driven config changes reuse spec 001's snapshot/restore: `saveChannel` does not reboot the radio whereas `saveLoRaConfig` does, so a custom-channel target applies the channel first and reverts it before the rebooting LoRa restore.
- "Beacon mode" traces to a community firmware module (`jkpg-mesh/mesh-beacon-Module`) whose protocol was upstreamed into `meshtastic/protobufs`. Whether the *official* firmware ships a first-class beacon module honoring `MeshBeaconConfig` is an implementation-time verification item for the proposed broadcast side (see research.md).

## Dependencies

- **[spec 001 — Local Mesh Discovery](../001-local-mesh-discovery/spec.md)** — the scan engine, state machine, dwell / reboot-reconnect handling, LoRa-config and primary-channel snapshot/restore (spec 001 FR-025 / FR-026), and the `ScanTarget` queue this feature plugs into. Beacon discovery does not function without an active scan (until passive listen, FR-015, is built).
- **`MeshtasticProtobufs`** — the regenerated upstream bindings for `MeshBeacon` (`MESH_BEACON_APP`, port 37) and `ModuleConfig.MeshBeaconConfig`. See [research.md](./research.md) for the protobuf / cross-platform parity analysis. No app-local wire types are defined (Constitution §V).
- Firmware supporting `AdminMessage` config changes and, for the proposed broadcast side, a firmware beacon module honoring `MeshBeaconConfig`.
