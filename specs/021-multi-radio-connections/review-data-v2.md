# Review V2: data, messages and services (feature/multi-radio)

Branch `feature/multi-radio` at `dc63a31d`. This pass re-checks the fixes for
`review-data.md` (D1–D19, commits `d79580f0` … `5e1e5b78`, T140–T166) and reviews the new code in
the same area: `MeshPackets+RadioRemoval.swift`, `AccessoryManager+RadioRemoval.swift`, the D-18
reset / remove / clear flows in `DeviceConfig.swift`, `AppSettings.swift` and
`BackupManagement.swift`, `MeshNetwork` in `LoRaChannelCalculator.swift`, the Siri / CarPlay
conversation changes, the key lookups, the aggregate window, the favorite vote, the Heard By
refresh, and the backup-merge and backfill changes. I read HANDOFF.md, tasks.md, plan.md and
spec.md again (D-18 is new), and the diff `bdca4708..HEAD` for my area.

Tests: the full suite passes in the iOS Simulator (iPhone 17 Pro): 3,442 Swift Testing tests in
598 suites, and 29 XCTests. No tracked file changed. None of the findings below is covered by a
test.

## Status of the first review

| | Status |
|---|---|
| D1 resets wipe every radio | Fixed (D-18). New risk in the reset buttons, see V2-1. |
| D2 channel delete by slot | Fixed: deletes what the timeline shows. |
| D3 undecoded copy hides the decoded one | Fixed: undecoded packets aren't recorded. |
| D4 backfill invents observations | Fixed: stops once another radio has observations. |
| D5 stale aggregate, foreign channel slot | Fixed (1-hour window, `channelSlot(toReach:)`). One case left, V2-6. |
| D6 Siri / CarPlay wrong radio | Fixed for notification and announce replies. Read-back and the CarPlay list still ignore the radio, V2-2. |
| D7 keyless / stale channel keys | Fixed: keys set on channel and LoRa arrival; keyless channels stay on their radio. |
| D8 mute and mentions | Fixed. |
| D9 backup merge in one transaction | Retries capped at three launches. Still one transaction (HANDOFF says so). Counting issue, V2-4. |
| D10 per-packet scans | Fixed for receptions, observations and ACKs. Reply and tapback lookups still scan (tasks.md says so). |
| D11 scan and range test | Fixed. |
| D12 TAK settings | Fixed. |
| D13 orphan observations | Fixed for eviction and Remove Node, not for Purge Stale Nodes, V2-3. |
| D14 backfill timing and attribution | Fixed: drained at launch and after a restore. |
| D15 fetches while rendering | Fixed in the code the first review listed. |
| D16 every radio ever known is "mine" | Partly: Remove This Radio exists but only for a connected radio (the owner's choice in HANDOFF). A sold or lent radio, or one only a merged backup knows, still can't be removed. |
| D17 favorite / ignored / verified | Fixed (vote of radios connected with this version). |
| D18 renumber on a shared serial port | Fixed. |
| D19 minors | Fixed, including the catalog strings (all new dialog strings are in `Localizable.xcstrings`). |

## New and remaining findings

Ranked most serious first. "Sure" is how confident I am that it happens as described.

### V2-1. The reset buttons can take the full-wipe path before the radio list has loaded

- `Views/Settings/Config/Forms/DeviceConfig.swift:226-229` (`otherRadios` loaded in `.task`),
  `:235-243` (`start`), `:288-300` (the single-radio `reset`).
- `start()` picks the single-radio path, which clears the whole store (`clearDatabase`) and
  disconnects `activeConnection`, whenever `otherRadios` is empty. `otherRadios` starts empty and
  is filled by an `await MeshPackets.shared.storedRadios()` in a `.task`. The reset buttons are
  enabled from the start, so a reset confirmed before that call returns takes the full-wipe path
  even with several radios' data in the store. It also disconnects the focused radio, not the one
  being reset, when that is another connected radio chosen in Settings' Node picker.
- The call is usually quick, but it waits behind whatever the ingest actor is doing. The launch
  backfill drain and the backup merge run there synchronously for seconds (tens of seconds for a
  big backup), so that's when the window is widest.
- The decision also ignores radios that are connected but haven't stored anything yet
  (`storedRadios` counts `lastConnected` or observations). If B has just been added and is still in
  its config download, resetting A takes the single-radio path while B keeps writing into the
  cleared store.
- Scenario: launch with a large backup still merging, open Settings › Node › "Connected: B" ›
  Device, tap Reset NodeDB and confirm within a few seconds. Every radio's data is erased, A is
  disconnected, and B is reset.
- Fix direction: keep the reset buttons disabled until the lookup has returned (an optional
  state), and count any other connected radio as "several".
- Sure: high that the path exists; low that people hit it, but when they do, it's a full wipe.

### V2-2. Siri read-back and the CarPlay list still ignore the radio

- `Intents/SearchForMessagesIntentHandler.swift:33-53`, `MeshtasticAppDelegate.swift:74-76`,
  `CarPlay/CarPlaySceneDelegate.swift:224,289,370`,
  `Intents/SendMessageIntentHandler.swift:184-200`.
- `SearchForMessagesIntentHandler` parses the new `:r<radio>` conversation ids but only uses the
  slot or node number. Reading "channel-2:rB" back returns slot 2 messages from every radio. The
  CarPlay list rows still use "channel-N" / "dm-X" without a radio, so reading a row from the
  CarPlay radio's list also reads other radios' messages in that slot. The mark-as-read that
  follows (`onRadio` returns true when the id has no radio) then marks those other radios'
  messages read too.
- The CarPlay list's unread counts and its read-back donation are scoped to the CarPlay radio
  (`belongs`), so a row can show no unread and still read out another radio's messages.
- A reply from a CarPlay list DM row carries "dm-X" with no radio and goes through the CarPlay
  radio (`:194`), even when the conversation with X is on another radio. Replies to announced
  messages and notifications are right now; this is only the list path. D-13 says a DM reply
  always goes through the conversation's radio.
- Scenario: A is the CarPlay radio with "Hiking" in slot 2, B has "Family" in slot 2. Tap Hiking
  in CarPlay: Siri also reads B's Family messages, and they're marked read on the phone.
- Sure: high for the search and mark-read code; medium for how often Siri takes the list path
  rather than the announce path.

### V2-3. Purge Stale Nodes leaves the purged nodes' observations

- `Persistence/UpdateSwiftData.swift:48` (`clearStaleNodes`, run at connect Step 8 when Purge
  Stale Nodes is on, `AccessoryManager+Connect.swift:479`).
- T146 deletes observations when a node is evicted or removed, but this third deletion path
  wasn't changed. With purging on, every connect leaves the purged nodes' observations behind.
  They keep growing, and when a purged node is heard again its old observations come back: Heard
  By and Node Detail list radios that heard it long ago (and haven't since).
- Sure: high.

### V2-4. One backup that keeps failing uses up the other backups' merge attempts

- `Persistence/NodeBackupManager.swift:786-806`, `Helpers/MeshPackets+BackupMerge.swift`
  (`mergeBackups`).
- `mergePendingBackups` adds one to `mergeAttempts` for every pending backup, saves the index,
  then merges them one after another in one call. If the first backup gets the app killed (the
  memory case from D9), the backups after it never ran but were still counted. After three such
  launches they're all given up and never merged, even though they'd merge fine on their own.
- The merge is still one transaction per backup with everything in memory, as HANDOFF says. The
  cap turns an endless crash loop into three crashed launches, not zero.
- Fix direction: count and save the attempt of one backup right before merging it, or merge the
  pending backups one per launch.
- Sure: high for the counting; medium for how likely a merge is to be killed.

### V2-5. Radios that can't be connected still can't be removed (D16)

- `Views/Settings/Config/Forms/DeviceConfig.swift` (the section only shows for a connected node),
  `Helpers/MeshPackets+MultiRadio.swift:34-37` (`localRadioNums`).
- Remove This Radio needs the radio connected. A radio the user sold or lent, and a radio only a
  merged backup knows, keep counting as the user's: their broadcasts are stored read, never
  notify, and show as the user's own bubbles. HANDOFF records this as a choice; I list it so it
  isn't forgotten, since the backup merge adds such radios for every switcher.
- Sure: high.

### V2-6. After a reset or removal, one remaining observation is copied whole, however old

- `Helpers/MeshPackets+RadioRemoval.swift:143,179-187` (`reaggregate`),
  `Helpers/MeshPackets+MultiRadio.swift:369-378` (`applyAggregate`, one observation).
- `removeRadioData` re-aggregates the nodes the removed radio shared with others. When only one
  other observation is left, `applyAggregate` copies it as it is (the 1-hour window only applies
  with several). If that one is a merged backup's months-old observation, the node's `lastHeard`,
  hops and signal jump back months. Online filters then hide it, and Purge Stale Nodes can delete
  it before a radio hears it again.
- Scenario: a switcher with merged backups resets the NodeDB of their only live radio A (the
  "several radios" path, since the merged radios count). Every node A shared with an old backup
  now shows the backup's last-heard date.
- Fix direction: leave the node's fields alone when the remaining observation is older than the
  node's own `lastHeard`, or apply the window to single observations here.
- Sure: high for the code; low impact beyond the display and the purge.

### V2-7. Deleting a radio's messages only counts connected radios' channels as shared

- `Helpers/MeshPackets+RadioRemoval.swift:156-162` (`deleteMessagesOfRadio`).
- The rule keeps channel messages on channels another of the user's radios has. It works that out
  with `channelKeysByIndex`, which needs the other radio's LoRa settings in the store. A radio
  only a merged backup knows has none (the merge doesn't copy config for its node), so its
  channels never count as shared, although its `ChannelEntity.channelKey`s are stored.
- Scenario: reset A with "Delete Messages"; B (from a merged backup) also had "Family". A's Family
  history is deleted, where D-18 says a channel another radio still has keeps its history.
- Fix direction: use the stored `channelKey` of the other radios' channels.
- Sure: high for the code; narrow case.

### V2-8. Minor

- `Helpers/MeshPackets+MultiRadio.swift:45`: the user's radios are re-read every 5 s. For up to
  5 s after a new radio's `MyInfoEntity` appears, other radios' packets don't look up its receptions
  and observations. A packet it already delivered and saved then counts as `.first` for the other
  radio: positions and telemetry get stored twice (text messages are protected by `messageKey`),
  and the node skips the aggregate for that packet. Clearing `lookupRadiosReadAt` when a
  `MyInfoEntity` is inserted (as `removeRadioData` does) would close it.
- `NodeFilterParameters.heardByNodeNums` isn't persisted and is nil at launch and after the
  choice changes, which means "no filter". With Heard By set, the lists and the map show every
  node until the first lookup returns.
- `TAKServerManager.shared.channel` is a slot number kept across a change of the TAK radio, so
  after picking another radio for TAK, CoT goes out on that radio's channel with the same number.
  The picker then shows the new radio's channel under that number.

## Checked and found fine

- Key lookups: receptions and observations only come from the user's radios, so looking them up
  by `radio:…` key for each radio finds what the scans found. ACK matching tries every radio's
  key, then the unkeyed legacy rows through the same index.
- `recordReception` returning `.untracked` for undecoded packets: the decoded copy from another
  radio is handled; `updateAnyPacketFrom` still records the undecoding radio's observation.
- The 1-hour window and `channelSlot(toReach:)`: the channel slot only comes from the focused
  radio; position exchange, client history and user-info exchange use it, from their button
  actions rather than view bodies; single-radio users still get `node.channel`.
- Channel keys: computed on the staged commit, every `channelPacket` and LoRa config; the
  keyless multi-radio queries (timeline, badge, tapbacks) are scoped to their radio;
  `deleteChannelMessages(query:)` deletes exactly the timeline.
- Launch backfill: runs only when messages wait for it, holds the handshake gate, attributes to
  the preferred radio; after a restore it drains with the restored radio as owner.
- Mute across radios and mentions of any of the user's radios; unchanged with one radio.
- Scan and range test: the scan radio's packets reach the engine once, whether or not another
  radio delivered first; the reconnect logic follows the scan radio.
- TAK settings: identity, role warning, Share Channels and the channel picker follow the TAK
  radio; the picker lists only its channels.
- The render-time fetches from D15 are gone; the Heard By set is looked up in a task and every
  15 s; offline radio names come from queried relationships or are loaded with the data.
- Favorite / ignored / verified vote; the user's change is written to every observation.
- `sameRadio` renumber matching.
- `removeRadioData`: messages, nodes (network comparison, favorites kept), observations,
  receptions, `MyInfoEntity` and own node on removal, each step saved, rolled back on error;
  `takeRadioOffline` hands the focus over first. Clear App Data disconnects every radio and names
  them. Restore asks first with several radios.
- Siri / CarPlay: conversation ids carry the radio only with more than one radio connected with
  this version, so single-radio ids, donations and replies are exactly as before; incoming,
  outgoing and re-donated intents share one builder.
- Single-radio paths: the resets are `main`'s full wipe when the store holds only that radio;
  CarPlay counts are unscoped with one radio; mute and mentions unchanged.
- Catalog: every new dialog and `.localized` string is in `Localizable.xcstrings`.

## Not covered

- The connection, focus, BLE restoration and lock-down fixes (C1–C14, the connections review),
  Widgets, the docs.
