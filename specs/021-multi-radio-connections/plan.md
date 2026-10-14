# Plan: Multiple Radios Connected at Once

**Feature**: 021-multi-radio-connections | **Spec**: [spec.md](./spec.md) | **Tasks**: [tasks.md](./tasks.md)

The design is §13 of [the research report](../../research/multi-radio-connections-report.md).
This file records how it is built here, and where it differs from the report because of the
decisions in [spec.md](./spec.md).

## Technical context

- Swift, SwiftUI, Swift Concurrency. SwiftData is the only persistence layer.
- Deployment targets are fixed: iOS 17.5, Mac Catalyst 14.6 (D-06). SwiftData's `#Unique` and
  `#Index` (iOS 18) are not available, so uniqueness is enforced in code or with `@Attribute(.unique)`.
- Project file is generated: edit `project.yml`, then run the pinned XcodeGen (`.xcodegen-version`,
  2.46.0). CI fails on drift.
- Tests: Swift Testing only. See `docs/developer/testing.md`.

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

The first multi-radio step (`2ab476ab`) made one radio "focused", with the full connect flow on
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
   - `MyInfoEntity`: `lastConnected`, `autoConnect`, `transport` (`sortOrder` and `displayColor`
     were dropped unused, T446)
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

Replaced by D-19 (see One window per radio): the composer's picker stays on iPhone and iPad,
defaulting to the window's radio, and goes on the Mac (W-14); the services no longer follow a
focused radio.

- Composer: a "via [radio]" control. The default is the focused radio, limited to radios that
  have the channel (by `channelKey`). DMs lock it to the conversation's radio.
- Settings › App Settings › "Radio for TAK / CarPlay & Siri / Watch": "Follow focused radio"
  (default) or a specific radio, set per service.

## One window per radio (D-19, decided 2026-09-29)

Spec: [windows.md](./windows.md). This replaces the focused radio. Numbers below were counted on
`feature/multi-radio` at `5ce2634d`.

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
   it (W-01); disconnecting keeps it, showing the radio off, and removing the radio closes it
   (W-02, revised 2026-10-04); the Radios menu lists the user's radios, connected or off, and
   reopens a hidden one; at launch each radio that reconnects gets its window back.
6. **No app-wide focus.** `activeConnection` and `additionalRadios` become one dictionary of
   sessions. `focusConnectedRadio`, `+FocusHandover`, `restoreDisplacedPreferred`,
   `PreferredRadio.connectFirstOverride`, `radiosFocusedThisRun` and the manager's focus-compat
   properties from step 1 go. `PreferredRadio` becomes the radios to reconnect
   (`MyInfoEntity.autoConnect`). BLE restore restores every radio iOS hands back the same way.
7. **Services** (W-08 to W-11): ask once per radio at its first connect whether to make it the
   Siri and CarPlay default; a `RadioEntity` (App Intents) so commands name a radio; a "set the
   default radio" command; TAK and Watch use their chosen radio or the only one connected.
8. **Adding, switching, composer** (W-12 to W-14): adding a radio always keeps the others, and
   the Keep Both / Switch question and setting go; switching is from Connect or the indicator's
   radio menu and never disconnects; the "Via" picker stays on iPhone and iPad and is hidden on
   the Mac.

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

## Delivery in layers (D-20, decided 2026-10-11)

`feature/multi-radio` stays the reference for the whole feature. It reaches `main` as a series of
pull requests, one layer each.

### Rules
- Each pull request starts from the latest `main`, does one thing, and is described by what the app
  and the radio do. Its description carries the notes for the admins: what changes with one radio
  and with several, a table of the entities, fields and keys it adds, how existing data is migrated
  or backfilled and what happens if that's interrupted, the risks and their tests, and what comes
  next and why this step is safe on its own.
- No stacking: a layer that builds on another is opened once that one has merged. Pull requests
  that don't depend on each other can be open at the same time; whichever merges second is rebased.
- Every radio behaves as `main`'s one radio, and one radio behaves as on `main`, apart from what a
  layer lists as changing.
- A layer is cut by bringing the final state of its files across from `feature/multi-radio` and
  removing the code paths that need several radios, as a fresh, short series of commits.
- After each merge, `main` is merged into `feature/multi-radio`, so it shrinks by what landed. A
  layer is re-cut, so that merge conflicts in every file it touched: changes made in a layer's review
  are made on `feature/multi-radio` too, and the merge back is checked file by file.
- A layer is cut by removing the code paths of the layers still to come.

### Checks for every pull request
- The full suite, with `main`'s own tests passing unchanged. A `main` test that has to change means
  behaviour changed, and the commit says why.
- `SchemaHistoryUpgradeTests`.
- Builds for iOS, Mac Catalyst and visionOS.
- SwiftLint with no new warnings, and the XcodeGen check.
- Checks on a device with a copy of real data: one radio as on `main` (switching, backup and
  restore, a preset change). From layer 2 on, also what the layer turns on with several radios, and
  its in-between state (for example the Mac before layer 3).
- Docs: the in-app user and developer docs the change touches, and this folder.

Nothing is cut until another agent has reviewed this plan and greenlit it (owner, 2026-10-11).

### Layer 1: the per-radio data model (`feature/per-radio-data-model`, T441)
Contents:
- Schema (V1, additive, D-16), all of the feature's:
  - `NodeObservationEntity`: each radio's view of a node (hops, SNR/RSSI, last heard, favorite,
    ignored, key verification, admin session, heard on current LoRa), unique `key` (`radio:node`);
  - `PacketReceptionEntity`: which radio heard a packet (SNR, RSSI, hops, relay, MQTT), unique `key`
    (`radio:sender:packet`), pruned at 30 days or 50,000 rows;
  - `ChannelEntity.channelKey`;
  - `MessageEntity`: `fromNum`, `toNum`, `localNodeNum`, `channelKey`, `messageKey` (unique,
    `sender:packet`), `systemEvent`, `previousChannelKey`; `messageId` loses `.unique`;
  - `PositionEntity.packetId`, `TelemetryEntity.packetId`;
  - `MyInfoEntity`: `lastConnected`, `autoConnect`, `transport`.
  - Which radios received each row stored once for several radios (D-21, T452): `receivedBy` on
    messages, positions, telemetry, PAX (which also gets `packetId`), waypoints and trace routes.
    Without it the link lives only in `PacketReceptionEntity`, which is pruned after 30 days.
- Writers: ingest fills the new columns for the connected radio: an observation per node, a
  reception per packet, message and channel keys, packet ids. Duplicates are removed by
  `messageKey`, and there's one notification per `messageKey`.
- The message lists key their rows by sender and packet id (`MessageEntity.listID`, T450), so two
  senders' messages that share a packet id both show. A reply or tapback names its target by
  packet id alone (the protocol carries no sender), so it attaches to the first of them, as on
  `main`; the description says so.
- Channel identity: `ChannelIdentity`, and `LoRaChannelCalculator` for the network part of the key.
- The backfill (`MultiRadioBackfill`) for rows stored before: in the background pass, and after
  `main`'s restore on a switch. Not at launch: nothing in layer 1 needs filled columns (rows
  without a key match by packet id), and a single-radio launch doesn't wait for it (T186). The
  `c1` channel keys and their conversion stay on this branch: they were never released. Older rows
  go to the store's own radio (`storeRadio`: the connected radio's record, else the store's only
  radio record), not the preferred radio: `main`'s switch sets that before it clears the store, so
  an app ended mid-switch would leave the old radio's rows under the new number. Errors are caught and logged. It's tried on copies of real
  stores before the pull request opens: a predicate SQLite can't run traps rather than throws (T379).
- Backups: the importer and copy helpers carry the new entities and fields (T028), and
  `NodeRenumber` moves the new node-number columns.
- The channel-change note (T377–T382, owner's call 2026-10-11): a channel's change leaves a note in
  its conversation. It doesn't need the keyed query: with one radio the channel list's query is
  `main`'s, by slot, and draws the note with `ChannelChangeRow`. What comes with it:
  - the channel list's preview skipping it, and Siri's message search skipping it;
  - the backup copy carrying it, and the backfill removing notes recorded twice;
  - Local Mesh Discovery pausing the recording while it steps through presets;
  - the reads of saved channel keys (T382, `storedChannelKeys`, `updateSavedChannelKeys`), which
    matter with one radio too: the staged channel refresh at reconnect wrote back a stale key.
- The settings forms and discovery reading the saved LoRa settings (T383): in layer 1 (owner's
  call, 2026-10-11, without the device check on `main`). The description says it may also fix
  `main`: a LoRa form showing and sending back a preset changed outside Settings, and a discovery
  scan restoring it.
- The config completion saves the download's records before the channel commit, which computes the
  keys from the saved LoRa settings. That order joins layer 1 (keys) and T445 (deferred saves):
  whichever merges second adds it, with a test that the keys see the new LoRa settings after a
  download.
- What ships with nothing reading or writing it yet, which the description lists:
  - `MyInfoEntity`'s `lastConnected`, `autoConnect` and `transport`, written by layer 2's
    remembered radios;
  - reception rows, observations, and `packetId` on positions and telemetry: written for the
    connected radio, read only from layer 2 (Heard By, the node list per radio, de-duplication
    across radios). Their cost is measured on a large store (`PerformanceSeedData`) before the pull
    request opens; if it shows, these writes wait for layer 2 at no loss: the backfill seeds
    observations from the nodes, and receptions only last 30 days.
  - `receivedBy`: the field, the tags written when a row is stored, and its
    backfill, which the background pass runs on every store. Shipping the backfill in layer 1's
    releases tags most stores before 2a reads the field. It rewrites the biggest tables once, in
    background chunks; that cost is part of the same measurement. `markReceived` (tagging a row
    another radio stored first) and the tagging before a radio is first shown go with 2a: with one
    radio there's nothing to tag after the fact.

What users see with one radio: as on `main`, apart from two things. Messages from two senders that
share a packet id stay separate, in the store and in the conversation. A channel change leaves a
note in the conversation.

Not in it: switching without the clear and restore, the backup merge (D-09), per-radio resets and
removal (D-18), the per-radio message queries, Heard By. Those come with layer 2, which turns them
on.

Size at the cut (2026-10-12): 34 app files, about 2,000 lines added; 9 test files, 1,600 lines;
docs, images and strings. Measured cost (iOS Simulator on a Mac, 3,000 nodes, 50,000 receptions,
saving every 20 packets): the per-packet node update went from 0.46 to 0.65 ms with the
observation, and the reception row adds 0.21 ms; the backfill filled 90,000 old rows in 100 chunks,
the slowest 0.36 s, in the background pass only.

### Opened alongside layer 1 (independent of it; the owner's yes, 2026-10-11)
- `refactor/radio-session` (T443): the connected radio becomes a `RadioSession`. Each event is
  tagged with the connection it came from, and version checks read the session's firmware
  (`connectedVersion`). No behaviour change. 11 files, about 270 lines. The in-memory per-radio
  fallback for version checks (T018) waits for layer 2b: it replaces `main`'s stored fallback,
  so after a relaunch the checks would be permissive while no radio is connected. The description says what it's for (the layers that
  give each radio its session), and if dropping a previous connection's late events changes what
  `main` does today, it says that's a fix.
- `perf/discovery-rssi` (T444): a nearby radio's signal strength in the Connect list updates at
  most every 2 s, rather than on every advertisement (T408, T413). About 4 files, 130 lines.
- `perf/config-download-saves` (T445): a connect's config download saves at its end rather than
  once per record (T410, T415, for one radio). About 5 files, 230 lines.

### Layer 2a: one database, switching as on `main` (T447; after layer 1 and the session refactor)
- Switching stops backing up, clearing and restoring: every radio's data stays in the one store.
- Every screen shows the connected radio's data only (D-21): nodes it has an observation for, with
  that observation's values; its direct and channel messages; the positions, telemetry and waypoints
  it received. One radio at a time works exactly as on `main`, switching included.
- The one-time merge of per-radio backups (D-09), each backup's rows tagged with its radio, and
  per-radio resets and removal (D-18). Pruning and eviction spare the user's radios (T424–T426).
- What users see: switching is the same as on `main`, without the copy and clear in between.
- Its own checks: `showRadio` timed on a large store (`PerformanceSeedData`), since it runs during a
  connect, ahead of the node database download; on iPhone with two radios, that a
  short drop of one doesn't change what's shown (needs a device check).

#### How the branch does it (T454)
- `ShownRadio`: the radio whose data the app shows. The one connected radio; with none connected,
  the last one (`PreferredRadio`); with several connected, none, and every radio's data shows.
  `AccessoryManager` sets it when a radio connects, finishes its handshake or disconnects, shortly
  after, with what's connected then.
  - A radio the app is bringing back after a drop still counts: the first radio while it
    reconnects on its own, the others while they wait in their reconnect loops. So only a
    disconnect, a removal or a switch changes what's shown. A radio away for good
    counts until the user disconnects or removes it, as `main` keeps trying (owner, 2026-10-12).
  - None while the store holds one radio, so nothing is filtered, as on `main`.
- Received by (T452): `receivedBy` on messages, positions, telemetry, PAX (which also gets
  `packetId`), waypoints and trace routes. It lists the radios that received the row
  (`",r1,r2,"`, `ReceivedBy`). Empty means not known yet, and shows for every radio.
  - Filled after each packet's handlers run, for the radio that delivered it, also when another
    radio delivered it first and the handlers were skipped (`markReceived`). The node-DB dump's
    positions and telemetry, sent messages, change notes, waypoints and trace routes are tagged
    where they're written.
  - The backfill tags older rows with the store's radio (messages with their `localNodeNum`), the
    backup merge with the backup's radio, `NodeRenumber` moves a radio's tag, and the backup copy
    carries the field. The background pass runs the backfill on every store, one radio or several.
  - Before a radio is first shown, rows still untagged are tagged with the store's own radio (the
    backfill's recorded owner, or the only other radio stored), so none of them show for the new
    one (`tagRowsBeforeShowing`). A joining radio's backfill counts untagged rows as
    pending too, and the recorded owner is kept until both kinds are done. Every writer tags its
    rows, so untagged means from before the field; once none is left the check isn't made again
    that session, since it reads whole tables.
- Node rows: with a shown radio, a node's last heard, signal, hops, channel, MQTT, favorite,
  ignored and key verification are that radio's observation. When the shown radio changes, every
  node is rewritten from the new one's observations (`showRadio`), and from all of them with
  several connected. A node's latest position is fetched again for every node the shown radio
  observes; a node it doesn't observe isn't listed for it and keeps its flag, and with every radio
  a node one radio observes keeps it.
- Screens, with a shown radio: the node list, map, contacts and node pickers list the nodes it has
  an observation of, plus itself (the Heard By lookup, which is hidden). Node details, the map's
  positions and waypoints, the logs and charts, trace routes, the channel timelines and unread
  counts read only rows it received. Direct messages are already its own (`localNodeNum`).
- A position fix close to the last one updates that row only when the row is the same radio's,
  and a fuzzed node's history is cleared only of the rows only that radio received.
- Pruning stale nodes and the node cap use every radio's observations, not the row: a node
  another radio keeps or heard recently stays. A favorite or ignore set with one radio shown is
  recorded on that radio's observation only. Heard By, the Via picker for direct messages and the
  radio's name in notifications show only with several connected.
- A store with one radio is left as it is: no radio shown, no rewrite, every node listed, as on
  `main`.
- Only the app sets the shown radio (`followsConnections`), not an `AccessoryManager` a test
  makes; tests set it for one task (`ShownRadio.$override`).
- Known limits: Siri's message search isn't limited to the shown radio; a waypoint is one row,
  so an edit heard by one radio shows for the others; rows from before `receivedBy` whose
  receptions have expired (30 days) are credited to the store's radio.
- Settled by the owner (D-22):
  - The position and telemetry history caps (25,000 positions a node, 5,000 readings a type)
    stay shared across radios. Messages are capped per radio already. The caps can be raised with
    the number of radios later.
  - On the Mac, a window whose radio is off shows it off in Messages, Nodes and Map, with Connect,
    unless its radio is the one shown or the user's only one (`showsRadioData`). A radio
    coming back after a drop isn't off. Layer 3 carries this; 2a's single window doesn't
    need it.

### Layer 2b: several radios at once (T453; after layer 2a)
- A session per radio and the handshake gate. Every radio reconnects as `main`'s does (T419–T432):
  after a drop, at launch, and on a restore.
- Screens show every radio's data together: one node list with Heard By, shared channel timelines,
  Via. The Connect screen's Add a Radio, notifications per radio. On iPhone and iPad, one window that
  switches radios and follows the radio used last. The scanning rule (T412–T418).
- The services per radio: MQTT per radio, the phone's position to every radio, and the radio
  chosen for TAK, CarPlay & Siri and the Watch (the Choose Radios sheet, W-15).
- The Mac uses the iPhone and iPad one-window model until layer 3 (`RadioWindows.areEnabled` off
  until then), with its own pass on the Mac.
- What users see: several radios connected at once. One radio at a time: as on `main` (D-21).

### Layer 3: the Mac's windows (T449)
One window per radio (D-19), the Connect window (T409, T411), hidden windows in the Window menu
(T433), the Dock opening a radio's window (W-16, T434), and the window rules for removals and
choices (T435–T438).

## Testing

- Unit (Swift Testing): session manager lifecycle with mock connections; BLE multi-peripheral
  continuation routing; writer de-duplication and scoping; aggregate recompute; `channelKey`
  cases; the V1 → V2 migration against `research/schema-history` fixtures; backup merge.
- Replay: feed captured `FromRadio` streams from two radios into one store and assert on the results.
- Snapshot: connect dialog, radio switcher, composer "via" control, per-radio node table.
- Manual tests with real radios (T130–T133 in `tasks.md`).

## Docs to update (repo policy)

- `docs/user/bluetooth.md` (line 36 says "only one is active at a time"), `docs/user/messages.md`,
  `docs/user/nodes.md`, `docs/user/settings.md`, `docs/user/carplay.md`
- `docs/developer/architecture.md`, `transport.md`, `swiftdata.md`, `deep-links.md`
- Regenerate bundled docs: `bash scripts/build-docs.sh --output Meshtastic/Resources/docs`
