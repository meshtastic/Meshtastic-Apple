# Review: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `d9ccf477`, compared with `origin/main...HEAD`. I read HANDOFF.md,
plan.md, spec.md, tasks.md and CLAUDE.md first, then: `MeshPackets.swift` (the diff and the
text, node-DB, admin and routing handlers around it), `MeshPackets+MultiRadio.swift`,
`MeshPackets+BackupMerge.swift`, `UpdateSwiftData.swift`, `MultiRadioBackfill.swift`,
`BackupMerge.swift`, `NodeBackupManager.swift` / `+Copies` / `+Import`, `NodeRenumber.swift`,
`ChannelMessageQuery.swift`, `DirectMessageQuery.swift`, the model changes
(`NodeObservationEntity`, `PacketReceptionEntity`, `MessageEntity`, `ChannelIdentity`,
`MyInfoEntity`, `PositionEntity`, `TelemetryEntity`, `MeshtasticSchemaV1`), the Messages, Nodes
and Settings views in the diff, TAK, CarPlay, App Intents and SiriKit, the Watch snapshot,
`AccessoryManager+RadioMQTT.swift`, `DiscoveryScanEngine.swift`, the notification path and
`Localizable.xcstrings`. Where the diff depends on unchanged code (`processFromRadio`,
`channelPacket`, `clearDatabase`, `DeviceConfig` reset, `TAKServerConfig`, CarPlay donations) I
read that too.

Tests: I ran the data-layer suites in the iOS Simulator (iPhone 17 Pro): SchemaHistoryUpgrade,
MultiRadioBackfill, BackupMerge, MultiRadioIngest, MessageKeyMigrationSpike, ChannelMessageQuery,
DirectMessageQuery, MultiRadioSchema. 51 tests in 8 suites passed. I didn't run the full suite
(the connections review did). No tracked file changed. None of the findings below is covered by
a test.

Ranked most serious first. "Sure" is how confident I am that it happens as described.

## 1. Resetting one radio wipes every radio's data

- `Views/Settings/Config/Forms/DeviceConfig.swift:192-212` (NodeDB reset), `:215-236` (factory
  reset), `Views/Settings/AppSettings.swift:214-226` (Clear App Data),
  `Persistence/UpdateSwiftData.swift:167` (`clearDatabase`).
- NodeDB reset and factory reset send the reset to the radio being configured, then call
  `clearDatabase`, which deletes every model in the shared store: every radio's messages and DMs,
  every `MyInfoEntity` and its channels, all observations, and the history the backup merge
  brought in. Before this branch the store held one radio, so this matched the radio; now it
  erases the other radios too.
- They also disconnect `activeConnection`, the focused radio. Settings' Node picker now lists the
  other connected radios ("Connected: <name>", `Settings.swift:768`), so resetting B's NodeDB
  from there resets B, disconnects A, and wipes everything. B stays connected and keeps writing
  into the emptied store without its `MyInfoEntity`.
- Clear App Data calls `disconnect()`, which only closes the focused radio. The other connected
  radios keep ingesting into the cleared store with no `MyInfoEntity`, so their channel lists are
  empty and `localRadioNums()` no longer knows them until they reconnect. The restore path
  (`Connect.swift:1159`) calls `disconnectAllAdditionalRadios()` first; these three don't.
- Scenario: A and B connected, a month of DMs on both. Settings › Node › "Connected: B" › Device ›
  Reset NodeDB. A disconnects, every message on both radios is gone, and the merged backups are
  already marked merged, so nothing brings them back.
- Sure: high.

## 2. Deleting a channel's messages deletes other radios' messages in the same slot

- `Persistence/UpdateSwiftData.swift:117-133` (`deleteChannelMessages`), called from
  `Views/Messages/ChannelList.swift:178`.
- The delete still matches `channel == index && toUser == nil`, with no radio and no
  `channelKey`. The channel list is the focused radio's, but slot numbers only mean something on
  one radio. It deletes every radio's messages in that slot number, and leaves the same channel's
  messages that came in on another radio in another slot (which the timeline shows, grouped by
  key).
- Scenario: A has "Hiking" in slot 1, B has "Family" in slot 1 (or B's history came in through
  the backup merge). Delete Messages on A's "Hiking": B's "Family" history is deleted. Messages
  of "Hiking" that B received in slot 2 stay in the timeline.
- Should use the same `ChannelMessageQuery` as the list (`messages()`), so it deletes what the user
  sees.
- Sure: high.

## 3. A broadcast one radio can't decrypt hides the copy another radio decrypted

- `Accessory Manager/AccessoryManager.swift:1059-1075`, `Helpers/MeshPackets+MultiRadio.swift:150-178`
  (`recordReception`).
- `recordReception` records every packet with an id and sender, decoded or not. The second radio
  to deliver a broadcast gets `.heardByAnotherRadio` and its handlers are skipped. If the first
  copy was undecodable (`payloadVariant` `.encrypted`, the first radio doesn't have that
  channel), nothing stored it, and the decoded copy from the second radio is dropped too.
- Firmware delivers undecodable broadcasts to the phone: `RoutingModule` is promiscuous and has
  `encryptedOk` with the default rebroadcast mode, and forwards broadcasts to the phone. Worth
  confirming in the device test, but the app code drops the message either way if such a copy
  arrives first.
- Scenario: A has only LongFast; B has LongFast and a private "Family" channel. Every "Family"
  message is heard by both. Whichever BLE link delivers first wins, so roughly half of "Family"
  messages (and positions and telemetry on it) never appear.
- Fix direction: only count a reception as handled when it was decoded (store a flag on the
  reception, or skip `recordReception`'s dedupe outcome for undecoded packets).
- Sure: high for the app logic; medium-high that firmware sends such copies.

## 4. The backfill invents observations for the preferred radio on every background pass

- `Persistence/MultiRadioBackfill.swift:120-146` (`backfillObservations`), `:39-49`
  (`runChunk`), `MeshtasticApp.swift:235`, `Helpers/MeshPackets+BackupMerge.swift:43-46`.
- The observation step is meant for old one-radio stores, but it runs on every background pass
  forever (and at launch before a merge), with `ownRadio = PreferredRadio.nodeNum`. It creates an
  observation for the preferred radio of every node that the preferred radio has no observation
  of, copied from the node's fields. After the upgrade those fields are other radios' views or
  the aggregate, so this fabricates "A heard it" rows for nodes only B or C heard. Since the
  preferred radio follows focus, over time every radio that was ever focused gets a copy of every
  node.
- Effects: the Heard By filter (node list, map, contacts) and the Watch's per-radio list include
  nodes that radio never heard; Node Detail › Heard By lists it; and the frozen copy joins the
  aggregate, so a node's hops and signal can stick at the values of the day the copy was made
  (see 5).
- Scenario: A focused, B connected. B hears 40 nodes A can't. Background the app. Heard By › A
  now lists those 40 nodes, and their rows show whatever hops B had at that moment until the
  copy is outvoted.
- The tests only cover the one-radio store (`MultiRadioBackfillTests.observationsAreCreated`).
  Fix direction: run the observation step only while the store has one `MyInfoEntity`, or mark it
  done once.
- Sure: high.

## 5. Node hops and signal come from stale observations, including for single-radio users

- `Helpers/MeshPackets+MultiRadio.swift:274-294` (`applyAggregate`, `isBetterPath`),
  `Persistence/UpdateSwiftData.swift:293-307`, `Persistence/BackupMerge.swift:194-199`.
- The aggregate picks the "best path" (RF over MQTT, then fewest hops, then newest) with no
  regard to age. An observation from a radio that is offline, or was last connected months ago,
  wins over the live radio's as long as it has fewer hops. `node.hopsAway`, `snr`, `rssi`,
  `viaMqtt` and `channel` then show that old value while `lastHeard` shows today.
- The backup merge (D-09) inserts an observation for the backup's radio for every node in the
  backup. So anyone who ever switched radios with the old app gets a second observation for most
  nodes at first launch, and from then on every packet takes the aggregate path. That includes
  the owner's always-on Mac radio, whose container holds the other radios' backups. HANDOFF says
  aggregation must only start with a second radio and the always-on radio must see no change.
- `node.channel` is one radio's slot number. The aggregate copies the best radio's slot onto the
  node, and the focused radio then uses it to send: `ExchangePositionsButton.swift:23`,
  `ClientHistoryButton.swift:20`, `exchangeUserInfo` (`AccessoryManager+ToRadio.swift:3165`).
  If that slot is another channel on the focused radio, the request goes out on the wrong channel.
- Scenario: B heard node N directly (0 hops, SNR +8) at a meetup in May. At home only A is
  connected and hears N at 3 hops. The node list shows N as Direct, SNR +8, heard 1 minute ago,
  and a position exchange with N goes out on B's slot number through A.
- Fix direction: ignore observations older than some window (or not from a connected radio) when
  picking the best path, and don't take `channel` from another radio.
- Sure: high for the logic; the visible effect depends on how many switchers have backups.

## 6. Siri and CarPlay replies can go to the wrong channel or through the wrong radio

- `CarPlay/CarPlayIntentDonation.swift:50,154` (`"channel-\(message.channel)"`, "Channel N"),
  `Intents/SendMessageIntentHandler.swift:125,147-160,173-181`,
  `Intents/IntentMessageConverters.swift:95-101` (`scoped` fallback),
  `CarPlay/CarPlaySceneDelegate.swift:445-458`.
- Incoming messages from every radio are donated with the receiving radio's slot number. A Siri
  or CarPlay reply resolves that number (from the conversation id or the "Channel N" group name)
  and sends it through the CarPlay & Siri radio in that slot number, which on that radio can be a
  different channel.
- `findChannels` falls back to every radio's channels when the CarPlay radio has no match, so
  "send to Family" on a radio without "Family" resolves B's slot index and sends it on the CarPlay
  radio's channel with that index.
- DM replies from Siri or CarPlay go through the CarPlay radio, not the radio the conversation is
  on. D-13 says a DM reply always goes through the conversation's radio. Notification quick
  replies do this right (`radioNum` in `userInfo`); the Siri path doesn't.
- CarPlay's channel unread counts group by slot number across radios (`:456`).
- Scenario: B receives "Family" in slot 2; A (focused, CarPlay follows focus) has "Hiking" in
  slot 2. Reply to the announced "Family" message by voice: it goes out on "Hiking".
- Sure: high for the code path; medium that Siri takes the conversation-id or group-name branch
  rather than failing (both lead to the same slot number).

## 7. A channel's timeline shows another radio's channel when its key is missing or stale

- `Helpers/MeshPackets.swift:926-970` (`channelPacket`), `Persistence/ChannelMessageQuery.swift:25-35`,
  `Views/Messages/ChannelMessageList.swift:377-378`.
- `ChannelEntity.channelKey` is only written by the text ingest of that radio
  (`channelKeysByIndex(updateStored: true)`), the background backfill (nil keys only) and backup
  copies. `channelPacket`, which stores the radio's channels at connect and after edits, never
  sets it. With more than one radio and a nil key, `ChannelMessageQuery` falls back to the
  single-radio query, `channel == index && toUser == nil`, with no radio filter.
- Scenario (nil): add radio B; before B receives a broadcast text and before any background pass,
  focus B and open its slot 1 ("Family"): it shows A's slot-1 "Hiking" messages. The unread badge
  (`ChannelEntity.unreadMessages`) counts them too.
- Scenario (stale): rename A's "Family" to "Family2". Until A receives a broadcast text, A's
  timeline still groups by the old key and shows B's "Family" messages.
- Fix direction: compute the key in `channelPacket` / the staged-channel commit, from the radio's
  LoRa config.
- Sure: high.

## 8. Channel mute and @mentions are judged by whichever radio delivered first

- `Helpers/MeshPackets.swift:2204-2214`.
- The notification checks `myInfo.channels` of the receiving radio for `mute`, and
  `MentionParser.containsMention(of: connectedNode, …)` for the receiving radio only. Mute is set
  on the focused radio's channel (`ChannelList.swift:147`). A message heard by two radios is
  handled once, by the first to deliver it.
- Scenario: mute "Family" in A's channel list. B also has "Family" and delivers first: the
  notification fires. Or: someone @mentions A; B delivers first, `containsMention(of: B)` is
  false, and with channel notifications off the mention is silent.
- Fix direction: resolve mute by `channelKey` across the user's radios; check mentions of any
  local radio.
- Sure: high.

## 9. The backup merge runs in one transaction at every launch until it succeeds

- `Persistence/BackupMerge.swift:47-62,134-168`, `Helpers/MeshPackets+BackupMerge.swift:38-74`,
  `MeshtasticApp.swift:160-166`, `Persistence/NodeBackupManager.swift:779-790`.
- `merge` loads every node, user, message, position and telemetry row of the backup, inserts the
  copies into the live context and saves once at the end, all on the ingest actor and holding
  the handshake gate. The caps allow 50k messages, 25k positions per node and 5k telemetry per
  type per node, so a long-lived backup can be hundreds of thousands of objects in memory at
  once. HANDOFF notes chunking may be needed; the consequence is worse than slow.
- If iOS kills the app for memory mid-merge, nothing is saved or marked, so the next launch runs
  it again: a crash a little after every launch, with no radio able to connect meanwhile (the
  gate is held). A deterministic `.failed` merge, and a backup whose checksum never matches, are
  also redone at every launch (checksum of each store file, staged copy, backfill), each time
  before the focused radio can connect.
- Scenario: a heavy user on an older iPhone with a big per-radio backup from a radio they
  switched away from.
- Fix direction: merge in chunks with a saved cursor, or give up after N attempts and leave the
  backup for a manual restore.
- Sure: medium (depends on backup sizes; I didn't measure).

## 10. Per-packet lookups scan whole tables, including for single-radio users

- `Helpers/MeshPackets+MultiRadio.swift:181-209` (`receptions`, `observations(ofNode:)`),
  `AccessoryManager.swift:1061`, `UpdateSwiftData.swift:293`, `MeshPackets.swift:1162,1206`
  (node-DB dump), `MeshPackets.swift:1946` (text dedupe), `MeshPackets.swift:452-455`.
- Every packet from every radio now does `fetch` on `PacketReceptionEntity` by
  `fromNum && packetId`, and `updateAnyPacketFrom` (plus each node in a node-DB dump) does
  `fetch` on `NodeObservationEntity` by `nodeNum`. Neither column is indexed (plan: no indexes);
  only the unique `key` columns are (Core Data builds `Z_<ENTITY>_UNIQUE_<ATTR>` indexes for
  unique attributes). Receptions are kept up to 100k rows while the app is active
  (`retentionRowLimit * 2`), so that's a full scan of up to 100k rows per packet, per radio. Both
  also build `insertedModelsArray` on every call.
- Removing `.unique` from `messageId` also dropped its index, so the text dedupe's
  `messageKey == nil && messageId == packetId` branch, and the reply/tapback/ACK-fallback lookups
  by `messageId`, now scan the message table.
- Single-radio users pay all of this: one radio still records a reception and does the
  observation lookup for every packet, and a node-DB dump of a few thousand nodes does a few
  thousand unindexed fetches.
- Fix direction: look up by `key` for each local radio (at most four indexed lookups), and drop
  the legacy `messageId` branch once the backfill is done. T132 should measure a busy mesh with a
  full reception table.
- Sure: medium-high that the scans happen; the cost needs measuring.

## 11. The discovery scan and range test lose packets another radio delivered first

- `AccessoryManager.swift:1075-1079` (scan packets), `:1153-1167` (range test),
  `:1192-1214` (neighbor info, beacons), `Services/DiscoveryScanEngine.swift:447,484-510`.
- The scan only takes its own radio's packets (`receivesPackets(from:)`), but that check sits
  inside `!handledByAnotherRadio`. When another radio on the same preset delivers a broadcast
  first, the scan radio's copy is skipped and the scan under-counts. The same happens to range
  test packets: the first radio's `wantRangeTestPackets` decides, and if it's off the packet is
  dropped even when the other radio has range test on.
- The scan's reconnect and "connection lost during dwell" logic reads `accessoryManager.isConnected`,
  `state` and `activeConnection?.connection.type`, which are the focused radio's. If focus moves
  during a scan, the engine can start dwelling while the scan radio is still rebooting.
- Scenario: A and B at home on LongFast; start "Analyze Current Preset" on A. About half the
  packets both hear are counted as not heard by A.
- Sure: high for the skip; medium for the focus case (needs a focus change mid-scan).

## 12. TAK settings still configure the focused radio and list every radio's channels

- `Views/Settings/TAKServerConfig.swift:23-25,61-63,220-232,282-283,690-696,721`,
  `Helpers/TAK/TAKMeshtasticBridge.swift:163`.
- The channel picker's `@Query` takes every `ChannelEntity` with `role > 0` in the store, from all
  radios (and merged backups), and keys `ForEach` on `index`, so indexes repeat. The chosen
  number (`TAKServerManager.shared.channel`) is then used as a slot on the TAK radio.
- The identity section (team, role), the device-role warning and Share Channels use
  `activeDeviceNum`, while CoT goes out through `session(for: .tak)`. With TAK set to B, the
  screen edits A's TAK config and warns about A's role.
- Scenario: TAK set to B, A focused. The picker shows "0 Primary" twice and a mix of both radios'
  channel names; picking A's "Team" (slot 2) sends CoT on B's slot 2.
- Sure: high.

## 13. Observations are never removed, so old ones come back

- `Helpers/MeshPackets.swift:590` (`evictNodesIfOverCap`),
  `AccessoryManager+ToRadio.swift:1449` (`removeNode`), `Model/NodeObservationEntity.swift`.
- Observations hold flat node numbers with no relationship, and nothing deletes them when a node
  is evicted or removed. Receptions have a retention cap; observations don't. They grow with node
  churn (events, busy meshes) and slow the unindexed `nodeNum` scans in 10. When an evicted or
  removed node is heard again, its old observations feed the aggregate (5) and the Heard By
  filter.
- Sure: high.

## 14. The live store's backfill may never finish on a Mac, and uses whoever is preferred then

- `Helpers/MeshPackets+MultiRadio.swift:305-308` (`shouldContinue` requires `!appIsActive`),
  `ChannelMessageQuery.swift:42-44`, `DirectMessageQuery.swift:38,57`.
- The backfill only runs in background passes (3 s each), or fully at launch when there are
  unmerged backups. A Mac that's always connected with its window open rarely goes to the
  background. Until it runs, old DMs have no `localNodeNum` and show under every radio's thread,
  and old channel messages have no `localNodeNum` or `channelKey`, so with a second radio they
  show in that radio's same-numbered slot (the `?? radioNum` in `bySlot`) even when it's another
  channel.
- It attributes rows to `PreferredRadio.nodeNum` at the time of the pass. After Backup Management
  › Restore of another radio's backup (still available, `BackupManagement.swift:188`), a pass run
  while a different radio is preferred assigns that radio's `localNodeNum` to the restored DMs.
- Sure: medium for the Mac (depends on how often Catalyst reports background); high for the
  attribution after a restore.

## 15. New SwiftData fetches while views render

- `Views/Messages/UserMessageList.swift:470-475` (via `radioLabel` in the picker),
  `Views/Nodes/Helpers/NodeHeardBySection.swift:44-50`,
  `Views/Nodes/Helpers/NodeFilterParameters+HeardBy.swift:18-33,65-70`,
  `Views/Settings/ServiceRadioPickers.swift:58-64`, `Views/Messages/UserList.swift:118`,
  `Views/Nodes/MeshMapMK.swift:210`, `Views/Nodes/NodeList.swift:319`.
- HANDOFF: nothing a view calls while rendering may fetch; a fetch there traps once the view's
  store is gone. `radioName` calls `getNodeInfo` (a `fetch`) for any radio that isn't connected,
  from the body. `NodeHeardBySection` does it inside NodeDetail, the view that crashed before.
  The Heard By filter runs a `fetchCount` and a fetch of every observation of the radio on each
  evaluation of the list and map filters; the map re-evaluates often.
- Scenario: open a node heard by A and an offline B during a database reset or restore (the
  store swap that the gate protects); or snapshot a NodeDetail with two observations.
- Fix direction: resolve names and heard-by sets in `.task` / `onChange` into `@State`, as
  `NodeHeardBySection.refresh()` already does for the observations.
- Sure: medium (the pattern is the one HANDOFF warns about; I didn't reproduce a crash).

## 16. Every radio the store ever knew counts as "mine"

- `Helpers/MeshPackets+MultiRadio.swift:34-37`, `Helpers/MeshPackets.swift:1959`,
  `Views/Messages/ChannelMessageList.swift:389-393`, `Views/Messages/ChannelMessageRow.swift:27-30`.
- "Mine" is every `MyInfoEntity`, and the merge adds one for every old backup. Nothing removes a
  radio. A radio the user sold or lent keeps counting: its broadcasts are stored read, never
  notify, and render as the user's own bubbles ("via X").
- Sure: high for the behaviour; how often it matters depends on users.

## 17. Favorite, ignored and key-verified follow the last node DB, not "any radio"

- `Helpers/MeshPackets.swift:1196-1205`, `applyAggregate` (doesn't touch them).
- FR-022 says the node row is "favorite or ignored if any radio says so" and lists key
  verification per radio. The code writes each radio's node-DB values onto the shared node, last
  one wins, and `observation.favorite/ignored/isKeyManuallyVerified` are stored but never read.
  HANDOFF mentions the flip-back for favorites; it also applies to ignore (an old radio that
  ignored a node hides it app-wide when it connects) and to key verification (B's dump clears a
  verification made on A).
- Sure: high (contradiction with spec.md).

## 18. Renumbering can match a different radio on the same serial port or TCP address (pre-existing)

- `Accessory Manager/AccessoryManager+FromRadio.swift:262-270`.
- When the incoming device id matches no `MyInfoEntity`, the code still renumbers any radio whose
  `peripheralId` matches. Serial ids hash the port path and manual TCP ids hash host:port, so a
  different radio plugged into the same USB port, or given the same address, matches even when
  both report different, non-empty device ids. Its whole history (DMs, `MyInfoEntity`,
  observations) is renamed to the new radio. The same check is on `main`; in the shared store
  it now renames one radio's data next to the others'.
- Fix direction: only fall back to `peripheralId` when the stored or incoming device id is empty.
- Sure: medium-high.

## 19. Minor

- `UserMessageList.swift:449-451`: with nothing connected and history on one radio only, the
  thread isn't filtered and "mine" is `PreferredRadio`, so that radio's sent messages render as
  incoming when it isn't the preferred one.
- `NodeHeardBySection` refreshes only when `node.lastHeard` changes; B hearing the node again
  doesn't refresh the table while A's time stays the latest.
- The backup merge treats a radio as known if any `MyInfoEntity` for it exists. Stores from the
  pre-fix "bleed" era can carry a stray one, which then blocks that radio's real backup from ever
  being merged (it's marked, not merged).
- A Backup Management restore replaces the whole shared store with one radio's backup. The backup
  taken just before is labelled with the focused radio only and marked merged, so the other
  radios' data in it won't come back on its own. The confirmation doesn't say other radios' data
  is replaced.
- `deleteUserMessages` removes the conversation on every radio while the thread shows one radio.
  Probably intended (the contact row is per node), but worth a line in the confirmation.
- New runtime `.localized` keys aren't in `Localizable.xcstrings` (so translators never see them):
  "on %@", "via %@", "Connect %@ to reply from it.", "%d hops", "CarPlay & Siri", "Apple Watch",
  and the two `OtherRadiosSettingsNote` sentences.
- `meshTrafficMonitor.recordInboundPacket()` counts every radio's copy, so the traffic rate the
  map throttles on grows with the number of radios.

## Checked and found fine

- Schema: every new attribute is optional or defaulted; the only new unique attribute on an
  existing entity (`messageKey`) is optional; the new entities are new tables. Dropping
  `messageId`'s uniqueness is covered by the spike and by `SchemaHistoryUpgradeTests` opening
  every release fixture and backfilling it (passes). No `VersionedSchema` added, per D-16.
- Restore importer and `NodeBackupManager+Copies` copy every new field (messages, channels,
  MyInfo, positions, telemetry, observations, receptions); `NodeRenumber` rewrites the new
  columns and keys and resolves collisions.
- Message de-duplication by `messageKey` (with the legacy `messageId` branch for rows without a
  key); the sent message and its echo merge; text ingest saves at once, so two pending rows never
  share a key. ACKs and admin-response ACKs try the delivering radio's key first.
- DM scoping: `DirectMessageQuery` per-radio predicates are correct, single-radio queries are the
  old ones, the Via picker, mark-as-read per thread, resend through the sending radio,
  notification deep links with `radio=`, and quick replies and tapbacks through the receiving
  radio.
- `ChannelMessageQuery` composition with `evaluate` needs iOS 17.4, within the 17.5 target.
  `PacketReceptionEntity.prune` terminates and handles nil `rxTime`.
- Backup merge: keyed and idempotent, live rows win, known radios skipped, backup files never
  written, the live backfill drained first, new backups marked merged, compaction carries the
  mark. A rerun after a save but before the index is written ends as "already known".
- Notifications: one per `messageKey`; nothing for the user's own radios; the subtitle and
  `radio=` only with more than one radio. App badge recounts are store-wide.
- MQTT per radio: unique client ids (UUID), topics and forward gate per radio, downlink filtered
  by the radio's own number, started and stopped per session, settings act on the configured
  radio.
- TAK send paths (V1, V2, generic CoT, fountain ACK), the node broadcast's self-exclusion, and the
  primary-channel check and fix use the TAK radio.
- Watch: "Follow Focused Radio" keeps the old snapshot; a chosen radio uses its observations.
- Discovery: the scan radio is fixed at start and config changes go to it through admin routing.
- Single-radio paths I traced: `updateAnyPacketFrom` with one observation writes the node as
  before; the channel and DM queries are the old ones; notifications unchanged. The exceptions
  are 4, 5 (for anyone with old backups) and 10.
- `Localizable.xcstrings` against `main`: no translations lost; the 17 removed keys had none.

## Not covered

- The connection, focus, BLE and restoration code (the connections review), phone position
  sharing beyond the send path, Widgets, the docs, and the full test suite.
