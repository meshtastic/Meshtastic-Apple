# Plan: Multiple Radios Connected at Once

**Feature**: 021-multi-radio-connections | **Spec**: [spec.md](./spec.md) | **Tasks**: [tasks.md](./tasks.md) | **Handoff**: [HANDOFF.md](./HANDOFF.md)

The design is §13 of [the research report](../../research/multi-radio-connections-report.md).
This file records how it is built here, and where it differs from the report because of the
decisions in [spec.md](./spec.md).

## Technical context

- Swift, SwiftUI, Swift Concurrency. SwiftData is the only persistence layer.
- Deployment targets are fixed: iOS 17.5, Mac Catalyst 14.6 (D-06). SwiftData's `#Unique` and
  `#Index` (iOS 18) are not available, so uniqueness is enforced in code or with `@Attribute(.unique)`.
- Project file is generated: edit `project.yml`, then run the pinned XcodeGen (`.xcodegen-version`,
  2.46.0). CI fails on drift.
- Tests: Swift Testing only. See `HANDOFF.md` for build and test commands.

## Architecture

```
Views ──▶ AccessoryManager (facade; today's API, forwards to the focused session)
              │
              ▼
       RadioSessionManager (@MainActor)
         ├─ sessions: [Device.ID: RadioSession]   (max 4, D-10)
         ├─ focusedSessionID
         ├─ discovery (always on)
         ├─ transports (BLE / TCP / Serial), each able to hold several connections
         └─ connect policy (Ask / Keep both / Switch, D-05)
              │
       RadioSession (@MainActor), one per radio
         ├─ device, connection, state, connect steps, heartbeats, config refresh
         ├─ nodeNum (replaces every activeDeviceNum / preferredPeripheralNum read)
         ├─ lockdown, firmware gate, OTA flag, packet counters, traffic monitor
         ├─ MQTT proxy instance (D-12)
         └─ position sharing task (D-12)
              │  packets tagged with radioNum
              ▼
       MeshPackets (@ModelActor): the ONE writer for all sessions
              │
       PersistenceController.shared.container: the ONE store (schema V2)
```

Rules:
- Inside a session, "me" means `session.nodeNum`. Outside, "mine" means any local radio's node
  number, from `MyInfoEntity.myNodeNum` rows.
- Nothing below the facade reads `AccessoryManager.shared`, `activeConnection`,
  `activeDeviceNum`, `UserDefaults.preferredPeripheralNum/Id` or `UserDefaults.firmwareVersion`.
  A lint rule enforces this once the migration is done.
- A single writer actor does all ingest de-duplication, so the second copy of a packet always
  sees the first.

## Schema V2

This follows report §13.3, with these differences for D-06:

1. **Freeze V1.** `MeshtasticSchemaV1` currently lists the live model types, so any model change
   would silently alter V1. Before touching any model, V1 becomes a namespace of nested frozen
   copies of all its models, byte-for-byte what shipped (SwiftData maps entities by class name,
   so nested `MeshtasticSchemaV1.NodeInfoEntity` is still the entity `NodeInfoEntity`). The
   `SchemaHistoryUpgradeTests` fixtures prove the frozen V1 still opens every released store.
2. **Message uniqueness without `#Unique`.** Add `messageKey: Int64 = (fromNum << 32) | packetId`,
   unique. `messageId` loses `.unique` and stays as the packet id for replies and tapbacks.
   Because a new unique column can't be added and filled in one lightweight step, it takes two
   stages:
   - V1 → V1_1 (custom): add the columns (not unique), and fill them in `didMigrate`.
   - V1_1 → V2 (lightweight): mark `messageKey` unique.

   The spike task confirms that SwiftData performs the uniqueness change as described. If it
   doesn't, the fallback is to keep `messageId` unique and de-duplicate by `(fromNum, messageId)`
   in the writer.
3. **No indexes.** Flat `fromNum`, `toNum`, `localNodeNum` and `channelKey` columns still avoid
   relationship joins. Measure with `PerformanceSeedData`.
4. New entities:
   - `NodeObservationEntity`: one per (radio, node). Uniqueness is enforced in the writer, with
     a `key` column (`"\(radioNum):\(nodeNum)"`) marked `.unique`.
   - `PacketReceptionEntity`: one per (radio, sender, packet), with a unique `key` and a
     retention cap (30 days or 50k rows, pruned on the existing background prune pass).
5. New attributes:
   - `ChannelEntity.channelKey`
   - `MessageEntity`: `channelKey`, `fromNum`, `toNum`, `localNodeNum`, `messageKey`
   - `PositionEntity.packetId`, `TelemetryEntity.packetId`
   - `MyInfoEntity`: `lastConnected`, `autoConnect`, `transport`, `sortOrder`, `displayColor`
6. `NodeInfoEntity` keeps its observer fields as aggregates, recomputed by the writer
   (report §13.3.2). Existing queries stay as they are.
7. Backfill (`didMigrate` of the custom stage): observations for the store's own radio,
   `localNodeNum`, `fromNum`/`toNum` from relationships, `channelKey` from that radio's channels,
   `messageKey`.
8. Backup merge (D-09): a one-time job after launch imports each backup through the existing
   staged-container path, migrates it to V2 scoped to its radio, and merges by the keys above.
   Its progress is saved, so an interrupted merge resumes.

## Connect flow (D-05)

- Tapping a radio while one or more are connected opens a dialog:
  - "Keep [A] connected and add [B]"
  - "Switch to [B]": disconnects the focused radio (or a chosen one at the cap); no data is cleared.
  - "Cancel"
  - a "Remember my choice" toggle.
- Setting: Settings › App Settings › "Connecting another radio": Ask / Keep both / Switch. Default: Ask.
- At 4 radios, "Keep both" is disabled, with the reason shown.
- `switchToDevice` and the backup → clear → restore path are removed. Backups stay as a user
  feature (snapshots of the whole database).

## Pickers (D-12, D-13)

- Composer: a "via [radio]" control. The default is the focused radio, limited to radios that
  have the channel (by `channelKey`). DMs lock it to the conversation's radio.
- Settings › App Settings › "Radio for TAK / CarPlay & Siri / Watch": "Follow focused radio"
  (default) or a specific radio, set per service.

## Side-by-side build (D-07)

Planned shape, pending the owner's answers (see `spec.md` Open items):
- A scheme and build configurations, "Meshtastic (Side by Side)", in `project.yml`:
  - `PRODUCT_BUNDLE_IDENTIFIER` gets the suffix `.sidebyside`, and the display name is "Meshtastic β";
  - a separate entitlements file drops the capabilities that need Apple approval for a new App ID
    (CarPlay communication, critical alerts, Siri, NFC, WeatherKit, associated domains);
  - the extensions and the watch app get matching bundle-ID suffixes.
- A different bundle ID gives a separate data container, so the released app's data is never touched.
- Seeding with real data: in the released app, Backup Management › back up now. Then, in the
  Files app, copy `Meshtastic/NodeBackups` into the side-by-side app's Documents. On launch,
  D-09's auto-merge brings it in.
- A BLE radio accepts one phone connection at a time, so don't point both apps at the same radio.

## Testing

- Unit (Swift Testing): session manager lifecycle with mock connections; BLE multi-peripheral
  continuation routing; writer de-duplication and scoping; aggregate recompute; `channelKey`
  cases; the V1 → V2 migration against `research/schema-history` fixtures; backup merge.
- Replay: feed captured `FromRadio` streams from two radios into one store and assert on the results.
- Snapshot: connect dialog, radio switcher, composer "via" control, per-radio node table.
- Manual device checklist in `HANDOFF.md`.

## Docs to update (repo policy)

- `docs/user/bluetooth.md` (line 36 says "only one is active at a time"), `docs/user/messages.md`,
  `docs/user/nodes.md`, `docs/user/settings.md`, `docs/user/carplay.md`
- `docs/developer/architecture.md`, `transport.md`, `swiftdata.md`, `deep-links.md`
- Regenerate bundled docs: `bash scripts/build-docs.sh --output Meshtastic/Resources/docs`
