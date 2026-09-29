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

Where this stands (2026-09-25): `RadioSession` exists and is `AccessoryManager.activeConnection`
(it replaced the `(device, connection)` tuple, so existing reads compile unchanged). Every
connection event carries the session it came from; data, log and RSSI events from a session that
is no longer active are dropped. `processFromRadio` and the `handle*` functions resolve the radio
from the session they are given. Connection lifecycle state (stepper, heartbeats, handshake
continuations, config refresh) still lives on `AccessoryManager`; it moves onto the session in
Phase 5, when there is more than one, because moving it earlier means reworking the single-connection
retry and teardown flow twice.

## Every radio the same (D-17, decided 2026-09-26)

The first multi-radio step (`40605d38`) made one radio "focused", with the full connect flow on
`AccessoryManager`, and every other radio an `AdditionalRadio` with a shorter flow of its own
(`AccessoryManager+AdditionalRadios.swift`). That was a shortcut, not the design: the owner
needs every connected radio to work the same way. Focus only picks the default for Settings,
sending and the services that follow it. It must never decide what a radio can do.

What the split left behind (read from the code, 2026-09-26):

| Area | Focused radio | Other radios |
|---|---|---|
| Connect | Steps 0–8 (`AccessoryManager+Connect.swift`) | Heartbeat, config and node-DB handshake, firmware check |
| Heartbeat (TCP, serial) | Repeating timer plus a response timeout that closes a silent link | Sends every 15 s; gives up only when a send throws |
| MQTT client proxy | `MqttClientProxyManager.shared` | `AdditionalRadioMqttBridge` |
| Lock-down | `LockdownCoordinator` and its passphrase sheet | Saved passphrase only, otherwise turned away |
| Firmware below `minimumVersion` | Stays connected behind the update screen | Turned away |
| Firmware warnings (`clientNotification`) | Shown | Dropped (no case in `processAdditionalFromRadio`) |
| Region presets, firmware edition | Stored on the manager | Dropped |
| Canned messages, ringtone, blank timezone | Requested / filled in | Not |
| Range test, store and forward | The focused radio's config decides for every radio's packets (`wantRangeTestPackets`) | Same flag |
| Status (`state`, `isConnected`, node count while loading) | `@Published` on the manager | Only the Connect tab row |
| Changing focus | — | `switchToDevice` disconnects both radios and runs a full connect and node-DB download for each |

The target is the architecture above: `RadioSession` holds all per-connection state, every radio
runs the same connect steps, `AccessoryManager` forwards its current properties to the focused
session so the views don't change, and focus is a pointer change. Steps, each its own commit
with the full suite passing and single-radio behaviour unchanged (tasks T068–T074):

1. Characterization tests of today's connect flow with a fake connection (order of requests,
   retries, lost bond, the Step 5 re-request guard, teardown). Only 6 test files touched the
   connect internals before this, so these are the safety net for the rest.
2. Move per-connection state onto `RadioSession`: stepper, event task, heartbeat timers, config
   refresh and its waiters, node-DB gate and first-node continuation, lock-down state, firmware
   edition, region presets, MQTT client, loading status, packet counters. The manager forwards.
3. Split the steps into per-radio work and once-per-app work: the ingest actor recycle
   (`MeshPackets.recreateShared`), the stale-node prune, the hardware catalog refresh and the
   preferred radio. Stopping discovery after a connect goes (discovery stays on, T063).
4. Every radio runs the per-radio steps; delete `AdditionalRadio`'s flow (`processAdditionalFromRadio`,
   `requestHandshake`, its heartbeat, `AdditionalRadioMqttBridge`, `handleAdditionalLockdown`).
5. Focus as a pointer change: `switchToDevice` for a connected radio, the focus handover and
   Disconnect on the focused radio stop reconnecting.
6. Lock-down and firmware prompts for any radio, naming the radio, instead of turning it away.
7. Clean-up (T066, T110, T111) and docs.

T070 in detail (what is per radio and what is once for the app, from `connect(to:)` and
`closeConnection()` as they are after T069):

| Where | Per radio | Once for the app (focused radio only for now) |
|---|---|---|
| Step 0–1 | connecting state, lock-down reset, transport connect, event loop, session | `activeConnection`, `activeDeviceNum` |
| Steps 2–5a | heartbeat, want-config (config), catalog refresh from the bundle, heartbeat, want-config (node DB) and its waits | image/link refresh (3b, network), `preferredPeripheralId` (Step 5) |
| Step 6 | version check | `UserDefaults.firmwareVersion`, the update gate (`firmwareUpdateRequired`) until T073 |
| Step 7 | set time, connected state, ingest actor recycle (the handshake gate keeps other dumps out; the retired actor keeps saving other radios' live writes, T151), manual connection list | Messages snapshot, update notifier |
| Step 8 | MQTT, heartbeat timer, Datadog connect action | stop discovery, stale-node prune, phone position loop, remembered radios |
| Teardown | connection state, config refresh, event loop, heartbeats, waits, channel refresh stage | Datadog context, focus handover, `activeDeviceNum`, update gate, lock-down, traffic monitor, position loop, image refresh, shared MQTT client, context save, disconnect buttons, discovery restart |

T070a splits the teardown into `tearDown(_ session:)` and the rest of `closeConnection()`.
T070b gives the steps a `ConnectAttempt` that holds the session Step 1 makes, so every step works
on its own radio's session and connection rather than `activeConnection`, and marks the app-wide
work as the focused radio's, in the same order as today. T071 then runs other radios through the
same steps with the app-wide work skipped, and adds per-radio connection status and teardown on
retry (Step 0 calls `closeConnection()`, which is the focused radio's).

T071 in commits (each with the full suite passing; the MultiRadio tests that build an
`AdditionalRadio` by hand, in six files, are rewritten against sessions as each part lands):

- T071a: connection status per radio. `RadioSession` gets its own status (connecting,
  communicating, retrying, loading the node DB with a count, connected) and its own "can
  disconnect"; the manager's `state`, `isConnected`, `isConnecting` and `allowDisconnect` show the
  focused radio's, and discovering/idle when nothing is focused. The connect stepper moves onto
  `ConnectAttempt`, one per radio being connected, so `disconnect()`, the heartbeat timeout and a
  link error cancel that radio's attempt.
- (Done with T071d in one commit: renaming first would have churned code T071d deletes.)
  T071b: one set of sessions. The focused radio is a pointer into it. Reconnects, remembered
  radios, the retired-session list, the Connect tab rows and `send(_:via:)` work on sessions. A
  link error or disconnect tears down that session; only the focused radio's also runs focus
  handover and discovery.
- T071c: an MQTT client proxy per session, one type for every radio (the shared manager and
  `AdditionalRadioMqttBridge` become one); the MQTT icon shows the focused radio's. Range test
  and store and forward read the receiving radio's config.
- T071d: every radio connects through the same steps (`isFocused: false` for the others), with
  the handshake gate, the bounded automatic connect and remembered radios as now. The app-wide
  parts of the handlers are the focused radio's (the preferred radio in `handleMyInfo`, the TAK
  bridge, event firmware notification defaults, the Datadog context); firmware warnings name the
  radio. Lock-down and old firmware on a radio that isn't focused keep today's handling until
  T073. `processAdditionalFromRadio`, `requestHandshake`, the additional heartbeat and
  `AdditionalRadioMqttBridge` are deleted. The characterization tests gain a second radio that
  must receive the same requests as the first.

Things the code can't settle, left for the device test: CoreBluetooth with four links, lock-down
firmware's reaction to a replayed status, and whether firmware warnings go to every phone link.

## Schema changes (D-16)

This follows report §13.3, adjusted for D-06 and for how this project actually evolves its schema.
"V2" below means "the models after this feature", not a new `VersionedSchema`.

1. **No schema freeze, no new versioned schema.** `MeshtasticSchemaV1` has listed the live models
   since 2.7.13, and every release since has added properties and relied on SwiftData's automatic
   lightweight migration. `SchemaHistoryUpgradeTests` opens a real store from each release to prove
   it. This feature does the same: additive changes only, each covered by those tests. (The earlier
   plan to freeze V1 and add V1_1/V2 with a custom stage would have meant copying 50+ models by
   hand, against the project's own pattern.)
2. **Message uniqueness without `#Unique`.** Add an optional `messageKey: String?`, unique, set to
   `"\(fromNum):\(packetId)"`. `messageId` loses `.unique` and stays as the packet id for replies
   and tapbacks. SQLite lets any number of NULLs sit under a unique index, so existing rows migrate
   with a NULL key and a backfill in code fills them in; new rows get the key on insert.
   **Spike done (T020):** `MessageKeyMigrationSpikeTests` proves on scratch stores that the
   single-step upgrade keeps every row, that two senders can then share a packet id, and that the
   same sender and id still collapse to one row.
3. **No indexes.** Flat `fromNum`, `toNum`, `localNodeNum` and `channelKey` columns still avoid
   relationship joins. Measure with `PerformanceSeedData`.
4. New entities:
   - `NodeObservationEntity`: one per (radio, node). Uniqueness is enforced in the writer, with
     a `key` column (`"\(radioNum):\(nodeNum)"`) marked `.unique`.
   - `PacketReceptionEntity`: one per (radio, sender, packet), with a unique `key` and a
     retention cap (30 days or 50k rows, pruned on the existing background prune pass).
5. New attributes (all optional or defaulted, so lightweight):
   - `ChannelEntity.channelKey`
   - `MessageEntity`: `channelKey`, `fromNum`, `toNum`, `localNodeNum`, `messageKey`
   - `PositionEntity.packetId`, `TelemetryEntity.packetId`
   - `MyInfoEntity`: `lastConnected`, `autoConnect`, `transport`, `sortOrder`, `displayColor`
6. `NodeInfoEntity` keeps its observer fields as aggregates, recomputed by the writer
   (report §13.3.2). Existing queries stay as they are.
7. **Backfill in code, not in a migration stage.** A resumable job after launch (on `MeshPackets`)
   fills observations for the store's own radio, `localNodeNum`, `fromNum`/`toNum` from
   relationships, `channelKey` from that radio's channels, and `messageKey`. Rows it hasn't reached
   yet have NULLs, which every reader must tolerate.
8. Backup merge (D-09): a one-time job after launch imports each backup through the existing
   staged-container path and merges by the keys above. Its progress is saved, so an interrupted
   merge resumes.
9. **Channel identity (T027, done):** `ChannelIdentity.key(...)` mirrors the firmware's
   `Channels::getName`/`getKey`: an empty name becomes the preset's channel name (or "Custom"), the
   1-byte PSK shorthand expands onto the default key, a secondary with no key borrows the
   primary's, and short keys are zero-padded. The key is `c1:<8-byte SHA-256 of the key, or
   "open">:<name>`, so the secret itself is never stored in it.

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

Replaced by D-19 (see One window per radio): the composer's picker goes, and the services no
longer follow a focused radio.

- Composer: a "via [radio]" control. The default is the focused radio, limited to radios that
  have the channel (by `channelKey`). DMs lock it to the conversation's radio.
- Settings › App Settings › "Radio for TAK / CarPlay & Siri / Watch": "Follow focused radio"
  (default) or a specific radio, set per service.

## Side-by-side build (D-07)

Local only, and Mac only (the owner's decision: nothing touches phones, tablets or watches).
Nothing below is committed: `.local/` and `MeshtasticSxS.xcodeproj/` are listed in
`.git/info/exclude`. `project.yml` and `Meshtastic.xcodeproj` are never touched.

- `.local/side-by-side/sxs.sh` drives everything (`setup`, `generate`, `install-mac`,
  `transfer-mac`). Settings are in `.local/side-by-side/config.env`.
- `generate.py` reads `project.yml` and writes `MeshtasticSxS.xcodeproj` with the pinned XcodeGen:
  - bundle ID `gvh.MeshtasticClientMulti` (extensions and the watch app follow), display name
    "Mesh Multi", Debug icon, signed with the owner's own team;
  - entitlements copied without CarPlay, critical alerts, custom-protocol, WeatherKit and
    associated domains (and, for Catalyst, Siri and NFC); keychain groups renamed to the new ID;
  - the TV targets and the test target are left out; `Package.resolved` is copied from the workspace.
- `transfer.py mac` seeds it with the Mac App Store app's data, container to container: live
  store, Documents (including every radio's backup, for the D-09 merge) and preferences. It only
  reads the App Store app. Whatever the side-by-side app held before is moved to
  `.local/side-by-side/transfers/<time>/`. Run only when the owner asks.
- Not carried over: keychain items (TAK certificates, MQTT and other saved secrets).
- The owner's main data is on the Mac: the radio that is always connected to it. The other radios
  were connected only now and then.
- Known quirks: both apps register `meshtastic:///`. A BLE radio accepts one app connection at a
  time, so don't point both apps at the same radio.
- Safety: a Mac Catalyst run of the normal project (tests included) shares the App Store app's
  container on this Mac. Run unit tests in the iOS Simulator only.

## One window per radio (D-19, decided 2026-09-29)

Spec: [windows.md](./windows.md). This replaces the focused radio. Numbers below were counted on
`feature/multi-radio` at `9787c7a1`.

### The window's radio

- `RadioWindow`: a `Codable`, `Hashable` value naming a radio by its peripheral id, which is known
  before the node number. The node number comes from the radio's session, or its `MyInfoEntity`.
- Radio windows are a `WindowGroup(for: RadioWindow.self)`. SwiftUI brings an already open window
  to the front when the same value is opened again, which is W-03.
- The window's radio reaches the views as an environment value, `\.windowRadio`, and the menu bar
  as a focused scene value (W-07).
- `AccessoryManager` gets lookups by window: `session(for: RadioWindow)`, `nodeNum(for:)`.
- iPhone: one window. Its radio is kept in `@SceneStorage`, so it opens on the same radio after a
  relaunch or a restore. Picking a radio in Connect sets it (W-04).
- The Connect window on the Mac and iPad (W-02) is its own `WindowGroup(id:)`, opened from the
  File menu ("Add Radio…") and at launch when no remembered radio reconnects.

### What reads the focus today

- 56 view files, 22 of them already changed on this branch, 34 untouched against `main`.
- `AccessoryManager.swift` (56 references), `+ToRadio` (22), `+FromRadio` (15), `+Connect` (11
  references and 30 `isFocused` branches), `+RadioChoice` (9), `+AdditionalRadios` (8), and a few
  in the others.
- Admin messages already route by the user they're from (`adminRoute(for:)`), so a Settings page
  that passes its window's radio as `fromUser` sends through that radio with no change below it.
- The message queries already take a radio (`ChannelMessageQuery`, `DirectMessageQuery`).

### Order of work

Each step keeps the app working and the suite passing. Until step 5 there is one window and its
radio is the focused one, so nothing changes for the user.

1. **Per-radio state onto `RadioSession`**: connection status, last error, "firmware update
   required", whether Disconnect is allowed, the connect stepper, and lock-down (one
   `LockdownCoordinator` per radio, or its state on the session). The manager keeps read-only
   properties that return the focused session's values, so the views don't change yet.
2. **`\.windowRadio`, and the views read it**, in groups: Connect, Settings, Messages, Nodes and
   the map, Tools and the rest. The one window's radio is the focused radio, so behaviour stays
   the same at every commit.
3. **A router per window.** Each window owns its `Router`. Deep links and notification taps go to
   a small registry of open windows, which picks the window by radio (W-05) and opens it if it's
   hidden. `MeshtasticAppDelegate`'s single `router` goes.
4. **App-wide work out of the connect steps.** The `isFocused` branches split into work done once
   per launch (device catalog and images, stopping discovery, stale-node prune, unread badges,
   the position loop, remembered-radio reconnect), run by whichever connect finishes first, and
   the per-radio state from step 1.
5. **Windows on the Mac and iPad.** A radio's window opens when it connects; closing it only hides
   it (W-01); disconnecting closes it (W-02); the Window menu lists the connected radios, and
   reopens a hidden one; at launch each radio that reconnects gets its window back.
6. **No app-wide focus.** `activeConnection` and `additionalRadios` become one dictionary of
   sessions. `focusConnectedRadio`, `+FocusHandover`, `restoreDisplacedPreferred`,
   `PreferredRadio.connectFirstOverride`, `radiosFocusedThisRun` and the manager's focus-compat
   properties from step 1 go. `PreferredRadio` becomes the radios to reconnect
   (`MyInfoEntity.autoConnect`). BLE restore restores every radio iOS hands back the same way.
7. **Services** (W-08 to W-11): ask once per radio at its first connect whether to make it the
   Siri and CarPlay default; a `RadioEntity` (App Intents) so commands name a radio; a "set the
   default radio" command; TAK and Watch use their chosen radio or the only one connected.
8. **Composer**: the "via [radio]" control goes. A window sends through its own radio, as a
   separate copy of the app would.

### Single-radio users

With one radio there is one window and one radio, as on `main`. Step 7's question isn't asked with
only one radio known; the services use the only radio.

### Testing

- Steps 1 to 4 keep today's tests, updated where they read focus state.
- Tests of the focus handover, the restore hand-over and the connect-first override are removed
  with the code in step 6; restore gets a test that every restored radio connects.
- New tests: window lookups, the window registry's choice for a notification (W-05), the ask-once
  rule (W-09), the intents with and without a radio name.
- Windows themselves (open, hide, close on disconnect, relaunch) go on the device checklist: the
  Mac build, run by the owner.

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
