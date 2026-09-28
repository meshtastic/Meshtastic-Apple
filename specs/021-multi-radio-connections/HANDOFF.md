# Handoff: Multiple Radios Connected at Once

Read this first if you are picking the work up. Update it in the same commit as the work.

**Feature**: 021-multi-radio-connections | [spec.md](./spec.md) · [plan.md](./plan.md) · [tasks.md](./tasks.md)

## Owner's rules (read before running anything)

- **Never access the owner's phones, tablets or watches**, not even read-only. No `devicectl`,
  no `pymobiledevice3`, no Xcode device installs. All testing happens on the Mac.
- **Never run the normal Mac Catalyst build of `Meshtastic.xcodeproj`, or its tests.** It has the
  App Store app's bundle ID (`gvh.MeshtasticClient`), so on this Mac it opens the same container
  as the App Store app, which holds the owner's most important data (the radio that is always
  connected to this Mac). Unit tests run in the **iOS Simulator** only. To run the app on the
  Mac, use the side-by-side "Mesh Multi" build.
- **Don't run `transfer-mac`** (copying the real data) until the owner asks. The owner will do the
  backup and the real-radio tests once they are happy with the work.

## Current state

- Branch `feature/multi-radio`, based on `origin/main` `ed36762c` (2026-09-25). Not pushed; the owner pushes.
- Commits below the feature work, carried into the branch:
  - `15baebb0` Keep every stored field when restoring a radio's backup (fix + tests)
  - `67fba963` Sync the string catalog with the current source
  - `d913970a`, `230eda8c` Research report and recommendation
- Done: tracking docs; split pull request branches (T005); side-by-side Mac tooling (T003/T004,
  local only). Phase 2 receive path (T010–T012, T019, part of T016) in `5671f9d2`; channel
  identity (T027) in `2a3e3653`; uniqueness spike (T020) in `6c173b7c`, which led to D-16.
  Phase 3 schema (T023–T025, T028, T029) in `7cf22678` and `3579188b`. Phase 4 ingest
  (T041–T049) in `10b6cba4`, `35a0936c`, `5ea963bd`. Phase 5 first step (additional radio
  sessions, per-peripheral BLE, no more store wipe on switch) and the connect dialog in
  `40605d38`; reconnect after a drop in `adfaad63`. Handshake gate (T064), remembered radios
  (rest of T063), bounded automatic connects and per-radio ACK matching in `5754e69b`. Per-radio
  direct messages with a "Via" picker, and sending/resending through a chosen radio (T085, send
  half of T084) in `2f5dcf6a`. Channels as one timeline across radios by `channelKey`, with a
  "Via" picker that sends in each radio's own slot (T083, T084) in `df9649f9`. Battery, signal
  and unread on connected-radio rows, and "via B" on your channel messages (T081, T086) in
  `d08fde38`. Node detail "Heard By" and favorite/ignore on every radio (T088, D-11) in
  `2af545de`. Focus keeps the previous radio (`6ae292ca`). Toolbar radio menu, Settings note and
  "on <radio>" in notifications (T082, T089, T091) in `bca4ecef`; the DM badge totals every radio
  (T090) in `2d7ab3fa`. Notification links open the right radio's thread (T091) in `d22f9206`;
  phone position to every radio (T101) in `3cb4e11a`; Disconnect on the focused radio hands the
  focus to another connected radio in `721bc873`; focus handover after a drop and the
  remembered-radio fallback at launch in `81b204a0`; connected-row snapshot (T092) in
  `42663087`; old per-radio backups merged into the shared store at launch (T030) in
  `e29241dc` and `6a050ce5`. The pre-DM contact refresh and auto-favorite through the sending
  radio in `da10664f`; the Heard By filter (T087) in `ec1437de`; lock-down and the firmware check
  on additional radios (T065) in `a32319ad`; an MQTT client proxy per additional radio (T100) in
  `8849b76f`; admin messages routed through the radio they concern, with the relaying radio's own
  passkey (T045, part of T089) in `8636d5f1`; the radio pickers for TAK, CarPlay & Siri and the
  Watch (T102–T105) in the commit after it. D-17 (every radio the same, T068–T074) and the
  review fixes (T140–T167, D-18 for resets) since. See tasks.md for the partial ones.
- Mesh Multi (`~/Applications/Mesh Multi.app`, side-by-side, own container) is rebuilt from the
  latest commit on this branch and ready for the first two-radio test below. Not yet run by anyone.
- Next up: the owner's device test (checklist below), which waits on hardware; don't rebuild
  Mesh Multi for it unless asked. Don't design around the focused/additional split: every radio
  works the same way (D-17). Removing the switch-era helpers (T066) waits for that test.
- Baseline and latest: the full suite passes in the iOS Simulator (3,468 Swift Testing tests plus
  the XCTests, about 55 seconds of test time). Run it with the simulator to itself: another
  session's test runs on the same simulator kill the test host partway.

## First two-radio test (Mesh Multi, Mac)

1. Open Mesh Multi, connect radio A from Available Radios (normal first connect).
2. On the Connect tab, "Add a Radio" lists radio B. Tap it; choose "Keep A and Add B".
   If A is still downloading its node list, B shows Connecting… until A is done (one handshake
   at a time; log line "waits for another radio's handshake").
3. B shows under "Also Connected", Connecting… then Connected. Log lines start with `🔗➕`.
4. Send a channel message from a third device: it appears once. Nodes heard by both radios
   appear once; the node list shows the best hops. Open that node: "Heard By" lists A and B.
   In the channel, the "Via" picker lists A and B; send one via B and check the third device
   gets it from B, and your bubble says "via B".
5. Direct messages: from a third device, DM radio A, then DM radio B. Open the conversation with
   that device: a "Via" picker shows A and B; each segment shows only its radio's messages.
   Reply with B selected: the log shows `📻 [B's short name] Sent message …`, and the third
   device sees the reply from B.
6. ⋯ → Disconnect on B: A stays connected, and the conversation's B segment says Offline with
   "Connect B to reply from it." Re-add B. ⋯ → Focus This Radio on B: nothing disconnects (log
   `🔀 Focusing B without reconnecting`); B is focused, A is under "Also Connected", Settings
   shows B, and both keep receiving (T072). Nothing is wiped.
7. Settings › App Settings › Connecting Another Radio: try Keep Both / Switch.
8. Power-cycle B while both are connected: it should drop from "Also Connected" and come back
   on its own (`🔗🔁` log lines). A disconnects nothing.
9. Quit Mesh Multi with both connected and reopen it: A reconnects as usual, then B comes back
   on its own ("remembered"). After ⋯ → Disconnect on B, a relaunch leaves B alone.
10. Favorite a node: the log shows "Set node … as favorite on" for A and for B. After the next
   node DB from either radio, the star stays.
11. Nodes tab › filter: "Heard By" lists A and B. Pick B: only nodes B has heard stay (the map
   and the contact list follow, since the filter is shared). Set it back to Any Radio.
12. If B has MQTT "Proxy to Client" on: log lines `📲 [MQTT] [B] connected; subscribing …` appear
   after B connects, separate from the focused radio's MQTT lines.
13. Worth watching: memory and CPU with two node dumps; any "Dropping an event from a
   disconnected additional radio" spam; whether BLE scanning while connected upsets pairing.
- Small pull requests, ready for the owner to push (each is one commit on `origin/main`):
  - `fix/restore-dropped-backup-fields` — the restore fix and its tests.
  - `chore/sync-string-catalog` — the string catalog sync.
  The same two commits stay at the bottom of this branch; after they merge upstream,
  `git rebase origin/main` drops them.

## In progress

- Review V4 (2026-09-27/28): `review-connections-v4.md` (F1–F4) and `review-data-v4.md`
  (R4-1–R4-2), checked in the files; all held. Fixed one commit each (`39ece463` … T205's
  commit, T200–T205 in tasks.md).
- Review V3 (2026-09-27): `review-connections-v3.md` (R1–R4) and `review-data-v3.md`
  (R3-1–R3-5), checked in the files; all held. Fixed one commit each (`c0000d3b` … `1b8ef1b8`,
  T190–T198 in tasks.md). Both reviewers' full runs were disturbed by another session's tests on
  the same simulator; a quiet run passed.
- Review V2 (2026-09-27): `review-connections-v2.md` (N1–N10) and `review-data-v2.md`
  (V2-1–V2-8), checked in the files; all held. Fixed one commit each (`5d517b58` … `dfc22694`,
  T170–T187 in tasks.md), including the owner's calls: no launch wait for a single-radio store
  (T186), removing a radio that isn't connected (T187), and N1: a locked radio that isn't
  focused gets its own passphrase sheet rather than waiting for the focus (T188).
- Review fixes (2026-09-27): every finding in `review-connections.md` (C1–C14) and
  `review-data.md` (D1–D19) is fixed, one commit each (`8fac5ca7` … `512dcb1c`, T140–T166 in
  tasks.md), except C13, which is `main`'s behaviour for the focused radio and is left as is
  (T167; a check for it is in the device test checklist). Choices made along the way that the
  owner should confirm:
  - Remove This Radio keeps favorites (D-18 gives the choice only for a reset). For a connected
    radio it sits with the resets in Settings › Device (only offered with several radios); a radio
    that isn't connected is removed from App Settings › Your Radios (T187, the owner's call:
    a radio can die and leave a ghost).
  - The node's hops and signal use observations heard within an hour of the newest
    (`NodeObservationEntity.currentWindow`); the channel slot comes only from the focused radio.
  - Favorite / ignored / verified: a radio only a merged backup knows doesn't vote.
  - A different radio on the same serial port or TCP address now joins the store as another
    radio; on `main` it took over the first radio's history (T165).
  - Restoring a backup asks first when the store holds several radios (on `main` it never asks).
  - A backup merge gets three launches; the merge itself is still one transaction (D9's
    chunking isn't done).
  - Siri / CarPlay conversation ids gain a radio suffix (`:r<num>`) only with several radios.
- D-17 (every radio the same) is done through T073: one connect flow, focus without
  reconnecting, and lock-down / old firmware prompting by name on any radio. Next: the device
  test when the owner's hardware is ready (checklist below). Also done since: T016, T018, T110,
  most of T111, T120, T121 and the string catalog sync (`30924072`). Left: T066 and the rest of
  T111 after the device test; more doc snapshots (T092); Phase 10 (T130–T135). T122 (bundled HTML)
  is the last step right before opening the pull request, by the owner's decision; `cmark-gfm`
  is installed.
  a test that has to change there means behaviour changed, so say why in the commit.
  When you start a task, mark it `[~]` in tasks.md and note it here.

## Blocked / waiting on the owner

- Real-radio testing: the owner is preparing two more radios and will test on the Mac when ready.
- The radio menu in the status indicator (`RadioSwitcherMenu` wrapping `ConnectedDevice`,
  `bca4ecef`, T082) goes against CLAUDE.md: the indicator is full and gets no controls. The owner
  is asking the project admin whether multiple radios justify an exception. Options: keep the
  menu and the "+N" badge; keep the menu without the badge (no extra width, but still a control);
  or remove both and change focus from the Connect tab (Focus This Radio, already there), later
  the iPad/Mac sidebar, optionally with a count on the Connect tab icon. Against it: the badge
  adds width on phones, and a focus change reconnects both radios, so an accidental tap isn't
  free. For it: focus applies to the whole app, the indicator already names the focused radio,
  and single-radio users see no change. If it's removed, also update `docs/user/bluetooth.md`
  (the "+1, +2 or +3" paragraph).
- Pull request size: D-02 plans one pull request for the whole feature; CLAUDE.md asks for small,
  single-purpose pull requests. The owner is discussing this with the project admin (spec.md ›
  Open items).

## Side-by-side build (local only, Mac only)

Not in git, on purpose (D-07): `.local/` and `MeshtasticSxS.xcodeproj/` are in `.git/info/exclude`.
If you are on another clone, this tooling does not exist there; `plan.md` › Side-by-side build
describes it well enough to rebuild.

```sh
.local/side-by-side/sxs.sh install-mac     # build and install ~/Applications/Mesh Multi.app (keeps its data)
.local/side-by-side/sxs.sh transfer-mac    # copy the App Store app's data. Only when the owner asks.
```

- Settings: `.local/side-by-side/config.env` (bundle ID, team, display name, extensions on/off).
- The transfer only reads the App Store app. It moves whatever Mesh Multi held to
  `.local/side-by-side/transfers/<time>/side-by-side-before/`.
- `sxs.sh generate` is only needed when `project.yml` changes.
- Verified 2026-09-25: generated settings for every target; Mac Catalyst build signed with team
  `6UB3T8FJYV` and installed to `~/Applications/Mesh Multi.app`, with its own container and
  keychain groups.
- Build pitfalls hit so far:
  - Mac Catalyst profiles reject the Siri and NFC entitlements, so the generator removes them for
    Catalyst only.
  - DerivedData must stay outside the repo, because the SwiftLint build phase lints everything
    under the repo root.
  - The app ignores an AppleScript quit (-128), so the scripts stop Mesh Multi with a signal and
    ask you to quit the App Store app yourself.

## Environment and commands

- `xcode-select` points at the command-line tools. Use:
  `export DEVELOPER_DIR=/Volumes/CrucialP3/Applications/Xcode.app/Contents/Developer` (Xcode 27).
- Simulator used so far: iPhone 17 Pro `CF2AE2BC-1D14-49DE-919B-0A840BC05B35`.
- Focused tests:
  ```sh
  xcodebuild test -workspace Meshtastic.xcworkspace -scheme Meshtastic \
    -destination 'platform=iOS Simulator,id=CF2AE2BC-1D14-49DE-919B-0A840BC05B35' \
    -only-testing:MeshtasticTests/<SuiteStructName> \
    -skipPackagePluginValidation -skipMacroValidation
  ```
- SwiftLint needs `DEVELOPER_DIR` set as above (it crashes loading SourceKit otherwise):
  `swiftlint lint --quiet <files>`
- XcodeGen, pinned to 2.46.0: download it as described in `CONTRIBUTING.md` (a copy may exist at
  `/tmp/xcg/xcodegen/bin/xcodegen`) and run `xcodegen generate`. Never commit a
  `project.pbxproj` that Xcode rewrote. Regenerate instead; CI byte-compares it.
- Xcode, when open, keeps re-serializing `Meshtastic.xcodeproj/project.pbxproj`. Discard that
  with `git checkout -- Meshtastic.xcodeproj/project.pbxproj` unless `project.yml` changed.
- Protobufs: keep the `protobufs` submodule on the committed pointer (`git submodule update protobufs`).
  `scripts/gen_protos.sh --no-pull` regenerates the Swift sources against it.
- Claude Code: `xcodebuild` and `swiftlint` fail inside its sandbox ("failed with exit code 0 but
  produced no further output"); run them with the sandbox off.
- String catalog: the feature's new strings aren't in `Localizable.xcstrings` yet (no feature
  commit has touched it). Sync it once near the end (T134). When a build changes `Localizable.xcstrings`, run
  `python3 scripts/copy-registry-translations.py` so the new `meshtastic.*` keys pick up the
  existing translations. Don't commit reordered or pruned catalogs without checking them.
- Terminal quirk in this environment: heredocs and multi-line quoted strings sometimes hang the
  shell. Write scripts and commit messages to files and pass the path.

## Gotchas found so far

- Schema changes: don't add a `VersionedSchema` or freeze V1 (D-16). Change the live models
  additively and keep `SchemaHistoryUpgradeTests` green. Any new unique attribute must be optional
  so existing rows migrate with NULL (proven in `MessageKeyMigrationSpikeTests`).
- `RadioSession` is a class: code holding a session sees later `updateDevice` changes, where the
  old tuple was a snapshot. Nothing relied on the snapshot behaviour (checked every
  `activeConnection` read), but keep it in mind.
- SwiftLint already warns about the length of `AccessoryManager` (type body),
  `processFromRadio`, `connect(to:)`, `upsertNodeInfoPacket` and `BLETransport` (type body, 476
  lines before this work). These warnings predate this work, and the feature's changes add a few
  lines to each. Splitting them up is part of T060.
- `MeshtasticSchemaV1` lists the live model types, and that is intended (D-16): every release since
  2.7.13 has changed them additively.
- `MessageEntity.messageId` is no longer unique (`10b6cba4`); `messageKey` ("sender:packetId")
  is. Both insert paths (ingest, `sendMessage`) set it, so a sent message and its echo still merge.
  ACKs and admin response ACKs try the delivering radio's key first
  (`MeshPackets.sentMessage(requestID:radioNum:)`). Tapback and reply lookups still go by
  `messageId` alone and can in rare cases match another sender's message; the lists already
  dedupe by id before building `Dictionary(uniqueKeysWithValues:)`, which would otherwise trap.
- `HandshakeGate` (T064) is held for the whole focused connect, including BLE pairing (up to
  90 s), and for an additional radio's config + node-DB handshake. Anything that runs while it's
  held must never call `connect(to:)` or `connectAdditionalRadio` and await it, or it deadlocks.
  `reconnectRememberedRadios()` only schedules reconnect tasks, which is why it's safe at the
  end of `connect`.
- A cancelled `BLETransport.connect` resumes its waiter but leaves CoreBluetooth's connect
  pending. Automatic connects (`connectAdditionalRadio(_:connectTimeout:)`) call
  `abandonPendingConnect(to:)` on timeout. The focused radio's connect is deliberately unchanged:
  its Step 1 retry relies on CoreBluetooth's pending connect.
- Direct messages: `DirectMessageQuery` only filters by radio when the conversation involves
  more than one radio, so single-radio queries are exactly the old ones. Rows with no
  `localNodeNum` (not yet backfilled) show under every radio.
- `sendMessage(…, viaRadio:)` skips the pre-DM contact refresh and auto-favorite through a
  non-focused radio; both are admin messages that still only go to the focused radio. A DM
  through another radio to a node it has no key for can fail with a PKI error until T060 moves
  admin sends onto sessions.
- SwiftData `fetch` does not see unsaved inserts. The new lookups (`receptions`,
  `observations(ofNode:)`) also scan `modelContext.insertedModelsArray`, like `findOrCreateNode`.
- Single-radio behaviour is kept on purpose: with one observation, `updateAnyPacketFrom` writes
  the node exactly as before and only mirrors into the observation. Aggregation starts with a
  second observation. Keep it that way; the owner's always-on radio must see no change.
- The backfill attributes old rows to `UserDefaults.preferredPeripheralNum`, which is the store's
  owner only while the switch flow exists. When T066 removes switching, run the backfill for
  each store before it is merged (T030), not after. `BackupMerge` does: it backfills the staged
  backup with its own radio as owner, and drains the live store's backfill before merging.
- Every radio's data goes through `processFromRadio(_:session:)` (T071). Anything app-wide in a
  handler must check `session === activeConnection` (see `handleMyInfo`: the preferred radio,
  event firmware defaults, TAK bridge; the Datadog context; `lastConfigRefresh`; the Messages
  snapshot; the lock-down coordinator). Admin requests a handler sends must go through
  `sendAdminMessageToRadio`, never `send(_:)`, which is the focused connection:
  `getCannedMessageModuleMessages` and `getRingtone` used `send(_:)` and asked the focused radio
  about another one until T071. Errors and disconnects of another radio go to
  `didReceiveAdditional`, never the focused radio's `.error` / `.disconnected` handling.
- `renumberStore` moved `preferredPeripheralNum` for any radio; it now only moves it when the
  radio being renumbered is the preferred one (T071). Tests that script several radios need
  distinct `MyNodeInfo.deviceID`s, or the app takes the second for the first renumbered.
- The ingest-actor memory recycle (connect Step 7, and every `ingestRecycleInterval` packets
  from any radio) is `recreateShared(invalidatingPrevious: false)`: the old actor keeps saving
  what other radios had in flight (T151), and gets a save queued at once and another 2 s later,
  since `updateAnyPacketFrom` and `recordReception` don't save themselves (T172). From the swap
  on it's marked retired and those two save as they happen, so the new instance sees their rows
  (T198); for those 2 s two contexts write the same store. Only the clear / repoint paths invalidate, and they
  invalidate earlier recycled instances too.
- Discovery while connected must not call `updateState(.discovering)`; `startDiscovery` only
  does that with no focused radio now.
- `SchemaHistoryUpgradeTests.fixtureInventoryCoversEverySwiftDataRelease` sometimes fails with a
  SQLite disk I/O error reading the bundled fixture's metadata. It predates this work and passes
  on a re-run.
- Backup merge (T030): a backup is merged once, recorded as `BackupEntry.mergedChecksum`. A
  backup of a radio the store already has a `MyInfoEntity` for is marked but not merged (it's an
  older copy; merging would resurrect deletions). New backups are marked merged when taken,
  and compaction carries the mark to the new checksum. The merge loads a backup's messages in
  one fetch; fine for the sizes seen so far, but a very large backup may need chunking. Since T159 a backup gets three launches (`NodeBackupManager.maxMergeAttempts`, counted before each attempt), so one that keeps failing or gets the app killed stops being retried; the merge itself is still one transaction.
  `NodeBackupManager`'s class body is over SwiftLint's limit (498 lines before, 502 now).
- The restore importer copies fields by hand. Every new stored attribute must be added to
  `NodeBackupManager+Import.swift` (`NodeBackupRestoreFieldTests` shows the pattern).
- A BLE radio serves one phone connection at a time. The released app and the side-by-side
  build must not both target the same radio.
- `#Predicate` with several optional comparisons (`localNodeNum`, `channelKey`, `?.num`) quickly
  hits "unable to type-check this expression in reasonable time". Split it into variants
  (`DirectMessageQuery`) or compose smaller predicates with `evaluate` (`ChannelMessageQuery`);
  SwiftData runs both (covered by store tests). `($0.localNodeNum ?? x) == x` is the cheapest
  "nil or x" test.
- `MyInfoEntity.unreadMessages` warns that `toUser == nil` in a predicate crashes or miscounts
  SwiftData on iOS 26 for badge counts. The conversation fetches already used it and still do;
  badge counts (`ChannelEntity.unreadMessages`) keep filtering `toUser` in Swift.
- With several radios observing a node, its favorite, ignored and verified flags are true if any
  radio connected with this version says so (FR-022, T164; a merged backup's radio doesn't vote).
  The user's change goes to every connected radio and onto every radio's observation
  (`setFavorite`, `setIgnored`). A radio that was offline when the user changed it will set the
  flag back when it next connects and dumps its node DB; syncing on reconnect is not built.
  Key verification has no app-side setter; it follows the radios' node DBs the same way.
- BLE restoration (T062): only the focused radio goes through the old restore path. Restored
  radios alongside it are claimed by the remembered-radio reconnect, so a restored radio that
  isn't remembered (`autoConnect` off) is released after `restoredStandbyGracePeriod`. If the
  focused restore fails, the others are released too; the remembered-radio fallback at discovery
  can bring one back as the focus. A radio restored still connected is the focused restore ahead
  of a preferred one still connecting, and the restore's wait only ends on its own peripheral's
  didConnect (T155). When a standby radio connects while the focused restore still waits, that
  radio takes over the restore and the waiting one joins the standby radios (T178). Every radio
  restored alongside the focused restore is remembered, so it's claimed after the focused
  connect, and a preferred radio passed over takes the focus back when it rejoins (T190). A focused
  restore still connecting with no other radio restored waits with no timeout and holds
  discovery off meanwhile, as on `main`.
- Connect Step 5 (found writing T068, fixed in T154): an answer to the node-DB request that
  arrives before `sendWantDatabase` starts waiting sets `RadioSession.databaseResponseArrived`,
  so the wait is skipped instead of timing out. `ScriptedRadio(replyDelay: .zero)` answers inside
  `send` to exercise it (`MultiRadioConnectFlowTests.immediateNodeDBAnswer`); the default stays
  20 ms, like a real round trip.
- Nothing a view calls while rendering may fetch from SwiftData: `checkIsVersionSupported` (and
  the `supports…` getters built on it) run in view bodies, and a fetch there traps once a view's
  store is gone. T018's first try did that and crashed NodeDetail's snapshot test; the fallback
  reads `knownFirmwareVersions` instead. `storedFirmwareVersion(for:)` is fine off the render path.
- The preferred radio is `PreferredRadio` (the radio reconnected and restored at launch; the
  focused radio whenever one is connected). `UserDefaults.preferredPeripheralId/Num` directly is a
  lint error outside `PreferredRadio.swift`. Code meaning "the radio I'm working with" uses its
  session, or `activeDeviceNum` for the focused one.
- The discovery scan runs on the radio focused when it starts (`scanRadioNum`) and only takes that
  radio's packets; the focus handover waits while it scans (the preset change reboots the radio).
- Focus when things go wrong (`AccessoryManager+FocusHandover.swift`): the Connect tab's
  Disconnect hands the focus to another connected radio at once (`disconnectFocusedRadio`).
  If the focused radio drops, `closeConnection` starts `scheduleFocusHandover`: after 30 s
  (rechecking every 10 s, up to 5 min) with nothing focused or connecting, the first connected
  additional radio takes the focus and the dropped one is remembered. When discovery starts
  with nothing connected, `scheduleRememberedRadioFallback` connects a remembered radio that's
  in range if the preferred one hasn't connected after 30 s, and remembers the preferred one.
  Neither fires after a deliberate disconnect (`userRequestedConnectionCancellation`), during a
  switch or an OTA. Watch for them in the device test: they change which radio is preferred.
- Editing tools: after changing a file with a script (`python3 /tmp/x.py`), re-read it before
  using the editor's find-and-replace on it. Once the editor applied an edit to its own stale
  copy of `UserMessageList.swift` and silently undid a script's refactor; `git diff` caught it.
- "Mine" in the views: channel rows use `ownRadioNums` (every `MyInfoEntity`); DM rows use the
  selected radio of the thread. `UserDefaults.preferredPeripheralNum` is only the fallback.
- Commit messages: write each to a new, unique file (`/tmp/mr-<topic>.txt`). `create_file`
  refuses to overwrite, and an old `/tmp/msgN.txt` from an earlier session once went into a
  commit unnoticed (fixed with `--amend`). Check `git log -1` after every commit.
- Lock-down on a radio that isn't focused (`AccessoryManager+RadioAttention.swift`) is untested on
  real lock-down firmware. Since T073 a locked or outdated radio stays connected with a
  `RadioAttention` and a prompt naming it; nothing turns it away. What the code can't tell: whether
  lock-down firmware answers the node-DB request (Step 5) while locked. If it doesn't, that
  radio's connect times out and retries, as the focused radio's already would; watch for it in
  the device test.
- MQTT per radio: two radios with proxy-to-client on the same broker both subscribe to the same
  channel topics, so the same broker traffic reaches both radios. The reception de-duplication
  stores it once, but it costs each radio's airtime, as with two phones.
- `AutoFavoriteRule` for a DM through radio B checks B's role; the pin then goes to every connected
  radio that isn't a client base (`setFavorite(_:node:radios:)`).

## Device test checklist (fill in during Phase 10)

- [ ] Connect radio A, then B → dialog shows; "Keep both" leaves both connected.
- [ ] "Switch" disconnects the focused radio without clearing any data.
- [ ] Four BLE radios connected; a fifth is refused with the reason shown.
- [ ] A channel shared by all radios shows one timeline; each message is stored once, with "heard by" details.
- [ ] A DM to radio B only appears in B's conversation; replying sends through B.
- [ ] Favorite a node → every connected radio favorites it.
- [ ] Power off one radio → it reconnects on its own; the others are unaffected.
- [ ] Background the app for 30 minutes, then foreground → all radios still connected.
- [ ] Kill the app while it's backgrounded → BLE restoration brings back every radio.
- [ ] TCP radio plus BLE radios together.
- [ ] Connect B alongside A: B's log shows the same connect steps as A (`[Connect] Step 1` to
  `Step 8`), B's canned messages and ringtone are requested on B's connection, and a firmware
  warning from B names it. On TCP, power B off without closing the link: B's heartbeat
  timeout drops it (A's doesn't change).
- [ ] Lock-down firmware on B with no saved passphrase: B connects alongside A, its row says
  Locked, and a prompt names B. Unlock opens B's own passphrase sheet (B's name at the top) and
  A stays focused (T188); after unlocking, B's real config and node DB arrive, and on B's next
  connect the saved passphrase unlocks it without asking. Watch whether B's connect retried
  while it waited (Step 5): with the sheet it no longer matters for unlocking. After unlocking A
  (focused) through its sheet, check that A's real config arrives without the app asking again;
  if it doesn't, the focused path needs the `sendWantConfig` the other radios' path already does
  (C13, T167).
- [ ] Reset NodeDB on B with A connected (Settings › Node › B › Device): only B disconnects and
  comes back; the app asks about B's messages. With A and B on the same preset and frequency the
  nodes stay; with B on another preset, the nodes only B heard go. Remove This Radio on B: B
  disconnects, isn't reconnected, and no longer appears as one of your radios.
- [ ] Clear App Data with A and B connected: the confirmation names both, both disconnect.
- [ ] Focused A dropped for more than 30 s: B takes the focus, A comes back alongside when it's in
  range, and the phone's position keeps going to both (T149).
- [ ] Old firmware on B: B stays connected, its row says it needs an update, Update focuses it and
  shows the update screen named B; the update screen's Disconnect hands the focus to A.
- [ ] App Settings › TAK / CarPlay & Siri / Apple Watch: pick B. TAK CoT goes out from B (log
  `📻 [B] Sending TAKPacket…`); a Shortcuts "Send a Group Message" without a radio goes via B;
  with B's node number while B is off, it fails. Reply to a notification from B: the reply goes via B.
