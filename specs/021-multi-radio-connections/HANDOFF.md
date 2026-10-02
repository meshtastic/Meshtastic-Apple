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
- Baseline and latest: the full suite passes in the iOS Simulator (3,519 Swift Testing tests plus
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

- D-19 (2026-09-29): one window per radio, no app-wide focused radio; part of 021, same pull
  request. Spec in `windows.md` (decisions W-01 to W-15), plan in plan.md › One window per radio,
  tasks in tasks.md › Phase 11 (T300–T325), all done 2026-09-29 except T315 (dropped, see its
  note). Nothing of the windows was run: the iOS Simulator suite and a Mac build (built, not run)
  pass; the device checklist below has what needs the owner's Mac, iPhone and Siri. Next: the
  owner's device test, then the full reviews of each area, then T122.
- Review V19 (2026-10-01): `review-connections-v19.md`, checking T374; no findings.
- Review V18 (2026-10-01): `review-connections-v18.md` (D1), checked in the files; held and fixed
  (T374).
- Review V17 (2026-10-01): `review-connections-v17.md` (U1–U2), checked in the files; both held and
  are fixed (T372, T373).
- Review V16 (2026-10-01): `review-connections-v16.md` (S1), checked in the files; held and fixed
  (T371).
- Review V15 and data V14 (2026-10-01): `review-connections-v15.md` (Q1) and `review-data-v14.md`
  (no findings), checked in the files; Q1 held and is fixed (T370). Its device check is on the
  checklist.
- Review V14 and data V13 (2026-09-30): `review-connections-v14.md` (P1–P4) and
  `review-data-v13.md` (R13-1–R13-2), checked in the files; all held. Fixed one commit each
  (T363–T368 in tasks.md). P3 and R13-1 were one problem, closed for every presentation of the one
  window rather than one at a time: with several radios, each is asked for only when the window
  shows nothing else (`WindowPresentationProbe`), keeps its turn, and is asked for again if it
  didn't come up. Also found while fixing P1: the test radio didn't reconnect after a disconnect,
  so the reconnect tests had only seen the first connect step; they now wait for the connect to
  finish.
- Review V13 and data V12 (2026-09-30): `review-connections-v13.md` (Z1–Z2) and
  `review-data-v12.md` (R12-1), checked in the files; all held. Fixed one commit each (T360–T362
  in tasks.md). Z1: the last radio left connected that drops comes back as the first radio once
  discovery sees it, the previous first radio remembered to join unless the user disconnected it,
  as the launch fallback has it. Z1's reboot and R12-1's sheet are on the device checklist.
- Review V12 and data V11 (2026-09-30): `review-connections-v12.md` (Y1–Y4) and
  `review-data-v11.md` (R11-1–R11-3), checked in the files; all held. Fixed one commit each
  (T350–T359 in tasks.md). The owner's calls: Y3 as proposed (Disconnect on the first radio with
  another connected makes that one the preferred radio), and the presentation order both reviews
  left for the device done now (T359: the gates, then the Choose Radios sheet, then another
  radio's prompt, one at a time). T359 and Y3's relaunch are on the device checklist.
- Review V11 and data V10 (2026-09-29/30): `review-connections-v11.md` (X1, W1–W7, minors) and
  `review-data-v10.md` (R10-1–R10-8), checked in the files; all held. Fixed one commit each
  (T330–T340 in tasks.md); after them, T341 took "focused" out of the code and T342 fixed the
  Settings note it turned up. R10-6 led to the owner's W-15: with several radios known, each service
  in use must have a radio chosen, and a chosen radio that's off is waited for, never replaced.
  Known and left as is: the Mac's Mesh Map window has no radio of its own, so it follows the radio
  connected first (`.focused`, `appState.router`) even when opened from another radio's window.
- Review V10 (2026-09-29): `review-connections-v10.md`, K1's fix and `connect(to:)` through
  Step 1 re-read whole; no findings. Next: one full review of each area after the device test,
  before T122; delta reviews only for fixes in that agent's area.
- Review V9 (2026-09-29): `review-connections-v9.md` (K1) and `review-data-v9.md` (no
  findings), checked in the files; K1 held and is fixed (T250 in tasks.md).
- Review V8 (2026-09-28): `review-connections-v8.md` (J1, one edge) and `review-data-v8.md`
  (R8-1, a cost to measure), checked in the files; all held. J1 and the flaky merge tests fixed
  one commit each; the edge and R8-1 recorded as notes (T240–T242 in tasks.md).
- Review V7 (2026-09-28): `review-connections-v7.md` (I1–I2) and `review-data-v7.md` (R7-1),
  checked in the files; all held. Fixed one commit each (T230–T232 in tasks.md). R7-1 was a
  policy choice: the owner chose per-radio message pruning (each radio keeps its newest 50,000;
  one radio prunes as `main`).
- Review V6 (2026-09-28): `review-connections-v6.md` (H1–H2) and `review-data-v6.md` (R6-1),
  checked in the files; all held. Fixed one commit each (T220–T222 in tasks.md).
- Review V5 (2026-09-28): `review-connections-v5.md` (G1–G4) and `review-data-v5.md`
  (R5-1–R5-2; G4 and R5-1 are the same), checked in the files; all held. Fixed one commit each
  (`2f150709` … `48628ca7`, T210–T214 in tasks.md).
- Review V4 (2026-09-27/28): `review-connections-v4.md` (F1–F4) and `review-data-v4.md`
  (R4-1–R4-2), checked in the files; all held. Fixed one commit each (`39ece463` … `f1cff86b`,
  T200–T205 in tasks.md).
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

- Since D-19 there's no focused radio. The code says "the first radio" for the one in
  `activeConnection` (connected first, `main`'s path) and "the window's radio" for what a window
  shows. Older notes and the review files still say "focused"; the names changed in T341:
  `RadioWindow.focused` → `.firstRadio`, `ConnectAttempt.isFocused` → `isFirst`, `connect(to:asFocused:)`
  → `asFirst:`, `disconnectFocusedRadio` → `disconnectFirstRadio`, `hasFocusedConnectInProgress`
  → `hasFirstConnectInProgress`, `focusedDeviceId` → `firstDeviceId`, `BLETransport.focusedPeripheral`
  → `firstPeripheral`, `restoreAsFocused` / `completeFocusedRestore` → `restoreAsFirst` /
  `completeFirstRestore`, `applyAggregate(focusedRadio:)` → `firstRadio:`.
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
- The owner's observation backfill decides from what the store held at the joining radio's
  connect Step 0 (T230). If an earlier connect of that radio got packets in and ended before its
  drain finished (the app killed mid-drain), its observations are already there and the owner
  gets none. Rare; left as is, since fixing it means keeping the answer across launches.
- Discovery while connected must not call `updateState(.discovering)`; `startDiscovery` only
  does that with no focused radio now.
- `BackupMergeTests.attemptCountedPerBackup` and `.strayRadioRowDoesNotBlockMerge` failed now and
  then with a checksum mismatch: the test store's file changed after its hash (a late WAL
  checkpoint). The helper now checkpoints the file and drops its journal before hashing (T241).
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
  connect, and comes back as it was (T190, T318). A focused
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
- The discovery scan runs on the radio connected first when it starts (`scanRadioNum`) and only
  takes that radio's packets.
- No focus handover any more (D-19, T316): when the radio connected first drops, the others stay
  and nothing takes its place; it's brought back by discovery as a single radio is, and a radio
  still connected alongside is never connected again as the first. When discovery starts with
  nothing connected, `scheduleRememberedRadioFallback` (`+LaunchFallback.swift`) connects a
  remembered radio that's in range if the preferred one hasn't connected after 30 s. It doesn't
  fire after a deliberate disconnect (`userRequestedConnectionCancellation`), during a switch or an
  OTA. Watch for it in the device test: it changes which radio is preferred.
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

- [ ] Connect radio A, then add B under Add a Radio: no question, both stay connected, and the
  window shows B (W-12). On the Mac, B opens in its own window once connected.
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
  nothing else moves (T188, T301); a passphrase that can't be sent keeps the sheet up with the
  reason; Lock Now in B's Settings closes B's link and it asks again on reconnect; after unlocking, B's real config and node DB arrive, and on B's next
  connect the saved passphrase unlocks it without asking. After unlocking A (the radio connected
  first) through its sheet, check that A's real config arrives without the app asking again; if it
  doesn't, A's path needs the `sendWantConfig` the other radios' already does (C13, T167).
- [ ] Reset NodeDB on B with A connected (Settings › Node › B › Device): only B disconnects and
  comes back; the app asks about B's messages. With A and B on the same preset and frequency the
  nodes stay; with B on another preset, the nodes only B heard go. Remove This Radio on B: B
  disconnects, isn't reconnected, and no longer appears as one of your radios.
- [ ] Clear App Data with A and B connected: the confirmation names both, both disconnect.
- [ ] Disconnect A (connected first) with B connected, then relaunch: B connects and A stays off
  (T352). With only A, Disconnect and relaunch: A connects again, as on `main`.
- [ ] Disconnect A, keep B, then make B reboot (save a LoRa setting in B's window): B comes back on
  its own, as the first radio, and A stays off (T360). Same with A dropped and away instead: B
  comes back, and A joins it once it's back in range. On iPhone with the window set to A, it shows
  B while B connects, then A again, reconnecting (as the launch fallback does; review V13 R13-2).
- [ ] A (connected first) out of range for minutes: B stays as it is, the window keeps showing A as
  reconnecting (nothing takes its place, D-19), A comes back on its own when it's in range, and the
  phone's position keeps going to B meanwhile.
- [ ] Old firmware on B: B stays connected, its row says it needs an update, Update shows B in the
  window with the update screen; the update screen's Disconnect disconnects B only.
- [ ] One thing at a time on iPhone (T359). Add B for the first time while B is locked and the
  window shows it: B's lock-down screen comes first, and the Choose Radios sheet comes up after B
  is unlocked. Same with B on old firmware (the update screen first). With the Choose Radios sheet
  up, lock or power-cycle a third radio C: C's prompt comes once the sheet is closed. With A's
  lock-down screen up, B needing the user: B's prompt comes once A is unlocked. Nothing is lost:
  each one appears in turn. Then with a sheet of the app's own open (a channel link's save sheet)
  while B is added for the first time: the Choose Radios sheet comes up a few seconds after that
  sheet is closed, and A's lock-down screen or B's prompt still come up afterwards (T362, T367).
  With a channel link's save sheet open, power-cycle a locked B: B's prompt comes up once the save
  sheet is closed, and if A locks meanwhile, A's lock-down screen comes after B's prompt is
  answered (T368). While B's prompt is on screen it stays up steadily: it doesn't close and come
  back every few seconds (the window check has to see the alert; review V15).
- [ ] Mac, two radio windows grouped as tabs: the Messages / Nodes / Map / Settings / Connect control
  sits in the same place in both tabs right after a window opens, without toggling the sidebar (a
  window lays out again a moment after it opens, by a one-point resize). If it doesn't, the nudge
  in `RadioWindowViews.swift` (`ToolbarLayoutNudge`) comes out and this is a known macOS quirk.
- [ ] Settings with A and B connected, in B's window: the note says these settings configure B and
  names A as the other radio (T342).
- [ ] iPhone: with A and B connected, Connect › B › Show This Radio and the indicator's radio menu
  switch the window to B with no reconnect (both radios' logs quiet); relaunch opens on B (W-04).
- [ ] Mac windows (D-19): each connected radio has its own window, the whole app for it; the
  Connect window lists them with Open and Disconnect; closing a radio's window only hides it
  (still connected, Radios menu reopens it); Radios › Disconnect acts on the key window's radio and
  closes its window; Radios › Add Radio… (⇧⌘N) brings the Connect window forward, or opens it
  when it's closed (never a second one); the File menu has no New Window or Add Radio; in the
  Connect window, Open on a radio only opens its window (it used to disconnect it too); after a relaunch each radio
  that reconnects has its window again; a notification tap opens the window of the radio it's
  about; the composer has no Via picker. With A's window and B's window open, navigating in one
  doesn't move the other.
- [ ] Siri and CarPlay (W-10, W-11, W-15): connecting B the first time while A is known shows the
  Choose Radios sheet, which doesn't close until CarPlay & Siri (and TAK if on, the Watch if
  paired) has a radio; TAK can be turned off from it instead. "Set my Meshtastic radio" and "Make
  B my Meshtastic radio" change it. A Shortcuts message without a radio goes via the chosen one;
  with A connected and the chosen B off it says "That radio isn't connected." and sends nothing;
  naming a radio that's off does the same. Siri's voice "send a message" goes via the chosen radio
  and, with it off, fails asking to open the app, without sending through A. Factory reset and shut down name the radio in their confirmation.
  Remove the chosen radio with two others left: the sheet asks again.
- [ ] App Settings › TAK / CarPlay & Siri / Apple Watch: pick B. TAK CoT goes out from B (log
  `📻 [B] Sending TAKPacket…`); a Shortcuts "Send a Group Message" without a radio goes via B;
  with B's node number while B is off, it fails. Reply to a notification from B: the reply goes via B.
