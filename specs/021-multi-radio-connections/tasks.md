# Tasks: Multiple Radios Connected at Once

**Feature**: 021-multi-radio-connections | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Handoff**: [HANDOFF.md](./HANDOFF.md)

## Format

`- [ ] T### [P?] Description`, followed by `— commit <sha>, verified: <how>` once done.

- `[ ]` todo · `[~]` in progress · `[X]` done · `[-]` dropped (say why)
- `[P]` means the task touches different files from its neighbours and can run in parallel.
- Keep this file current in the same commit as the work it describes.

Everything lands in one pull request (D-02). Phase order is the planned build order. Earlier
phases don't change behaviour and keep the app shippable, which makes a rebase onto `main` easy.

---

## Phase 1: Setup

- [X] T001 Rebase onto `origin/main`, create `feature/multi-radio` — branch created 2026-09-25 on top of `ed36762c`.
- [X] T002 Create the tracking docs (this folder) and point the SpecKit block in `.github/copilot-instructions.md` at `specs/021-multi-radio-connections/plan.md` — verified: files present, pointer updated.
- [~] T003 Side-by-side build (D-07), local only: `.local/side-by-side/` generates `MeshtasticSxS.xcodeproj` (bundle ID `gvh.MeshtasticClientMulti`, "Mesh Multi", owner's team `6UB3T8FJYV`, reduced entitlements) with the pinned XcodeGen. Not committed by design (see plan.md). Mac only. Verified: generated settings per target; Mac Catalyst build signed, installed, own container.
- [X] T004 Seeding: `sxs.sh transfer-mac` (container to container, read-only on the App Store app). Documented in `HANDOFF.md`. The owner runs it when ready.
- [X] T005 Split the standalone changes into their own pull requests: `fix/restore-dropped-backup-fields` (`b9974ada`) and `chore/sync-string-catalog` (`f405e7b8`), each one commit on `origin/main` — verified: identical content to `15baebb0` / `67fba963`.

**Checkpoint**: the side-by-side app installs next to the released app with its own data.

## Phase 2: Session extraction (no behaviour change)

- [X] T010 Add `RadioSession` (`Meshtastic/Accessory/Radio Session/RadioSession.swift`): device, connection, identity — commit `5671f9d2`, verified: `RadioSessionTests`, full suite. The rest of the per-connection state listed in the plan (stepper, event task, heartbeats, config-refresh owner, DB gate, first-NodeInfo continuation, lockdown, firmware gate, OTA flag, counters, `expectedNodeDBSize`, region presets, firmware edition) moves in T060, when there is more than one session (see plan.md › Architecture).
- [X] T011 `AccessoryManager.activeConnection` is a `RadioSession?` (replaced the tuple; reads unchanged; `updateDevice` changes it in place) — commit `5671f9d2`.
- [X] T012 Pass the session explicitly: every event is tagged with its session; `didReceive(_:from:)` drops data/log/RSSI from a stale session; `processFromRadio` and each `handle*` take the session — commit `5671f9d2`.
- [ ] T013 [P] Move the connect steps (`AccessoryManager+Connect.swift`) onto the session. Deferred to T060.
- [ ] T014 [P] Move the ToRadio builders onto the session (`RadioSession+ToRadio.swift`), with facade forwarders. Deferred to T060.
- [ ] T015 [P] Add `TransportDelegate`; remove `AccessoryManager.shared` from `BLETransport` restoration and `TCPTransport.manuallyConnect`.
- [~] T016 [P] Replace `UserDefaults.preferredPeripheralNum` reads in ingest and services with the session's node number. Done for ingest (`upsertNodeInfoPacket`, `ingestPassiveBeacon`) in `5671f9d2`. Left: `DiscoveryScanEngine` (12 reads; "which radio runs the scan", decided in Phase 7), `BLETransport` restoration, and the views (Phase 6).
- [-] T017 [P] Make `MqttClientProxyManager` an instance per session, with a per-instance forward gate. Superseded by T100 (`8849b76f`): additional radios get their own instance and gate; the focused radio keeps the shared one.
- [ ] T018 [P] Version gates read `session.firmwareVersion`; remove `UserDefaults.firmwareVersion` reads.
- [X] T019 Unit tests: session identity, in-place updates, stale-event dropping with a mock `Connection` — `RadioSessionTests`, commit `5671f9d2`.

**Checkpoint**: all tests pass; the app behaves exactly as before with one radio.

## Phase 3: Schema changes (D-16: additive, lightweight, no new VersionedSchema)

- [X] T020 Spike: move message uniqueness to a sender-scoped key — commit `6c173b7c`, verified: `MessageKeyMigrationSpikeTests` (5 cases, incl. the single-step upgrade). Outcome recorded as D-16.
- [-] T021 Freeze V1. Dropped by D-16: the project changes live models under V1 and proves every release store still opens (`SchemaHistoryUpgradeTests`).
- [-] T022 `MeshtasticSchemaV1_1` / `V2`. Dropped by D-16.
- [X] T023 Add `NodeObservationEntity` and `PacketReceptionEntity` (added to `MeshtasticSchemaV1.models`) — commit `7cf22678`, verified: `MultiRadioSchemaTests`, `SchemaHistoryUpgradeTests`.
- [X] T024 Add the new attributes (plan.md › Schema changes item 5), all optional or defaulted — commit `7cf22678`. `messageKey: String?` is unique; `messageId` lost `.unique` in `10b6cba4`, once every insert set the key.
- [X] T025 Resumable backfill (`MultiRadioBackfill`, run by `MeshPackets.runMultiRadioMaintenance` in the background maintenance pass, skipped during a device switch) — commit `3579188b`, verified: `MultiRadioBackfillTests`; `SchemaHistoryUpgradeTests` backfills every release store.
- [-] T026 Lightweight stage V1_1 → V2. Dropped by D-16.
- [X] T027 `channelKey` derivation (`ChannelIdentity.swift`) plus tests — commit `2a3e3653`, verified: `ChannelIdentityTests` (16 cases).
- [X] T028 Update the backup importer for the new entities and attributes; `NodeRenumber` moves the new node-number columns and keys too — commit `7cf22678`, verified: `MultiRadioSchemaTests`.
- [X] T029 Migration tests: every release fixture opens with the new models, arrives with empty new columns, and is backfilled and saved — commit `3579188b`.
- [X] T030 Backup merge job (D-09): resumable, keyed merge, originals kept — commits `e29241dc` (copy helpers shared with the restore) and `6a050ce5` (`BackupMerge`, `MeshPackets.mergeBackups`, `NodeBackupManager.mergePendingBackups`, launch hook). Verified: `BackupMergeTests` (two synthetic radio backups: rows added, live wins, idempotent, known radio skipped, bad checksum kept, new backups not pending), full suite. Runs once per backup at launch, holding the handshake gate; recorded as `BackupEntry.mergedChecksum`.

**Checkpoint**: an existing store and its backups upgrade with nothing lost; the app still runs with one radio.

## Phase 4: Ingest scoping and de-duplication

- [~] T040 Every `MeshPackets` entry point takes `radioNum`. Done for the ones that need it (receptions, observations, text, telemetry, routing, admin, node info). Left: `upsertPositionPacket`, `waypointPacket`, `paxCounterPacket`, `upsertNodeStatusPacket` (they don't depend on the radio yet).
- [X] T041 Receptions: upsert `(radioNum, from, id)`; a broadcast another local radio already delivered skips the handlers (repeats from the same radio are handled as before) — commit `10b6cba4`, verified: `MultiRadioIngestTests`.
- [X] T042 Observations: `updateAnyPacketFrom` and the node-DB dump write the radio's observation; one observation → node written directly as before; several → `NodeObservationEntity.applyAggregate` — commit `10b6cba4`. Follow-up: other paths that write node hops/last-heard directly (`upsertNodeInfoPacket` new-node branch, position/telemetry hop updates, trace-route last-heard) are last-writer-wins until the next aggregate.
- [X] T043 Text messages (ingest and send): set `fromNum`, `toNum`, `localNodeNum`, `channelKey`, `messageKey`; de-duplicate by `messageKey` (falls back to `messageId` for rows without a key) — commit `10b6cba4`. ACK matching (`routingPacket`, `adminResponseAck`) now tries the delivering radio's `messageKey` first (`5754e69b`, `MeshPackets.sentMessage(requestID:radioNum:)`).
- [X] T044 [P] Positions and telemetry store their `packetId`; cross-radio duplicates are already stopped by T041 — commit `5ea963bd`.
- [~] T045 [P] Admin sessions: passkeys written on the asking radio's observation — commit `5ea963bd`. Reading them per radio in the send path waits for T060 (remote admin through a chosen radio).
- [X] T046 [P] Trace routes: originator is the session's radio — already true since `5671f9d2` (`handleTraceRouteApp(_:session:)`).
- [~] T047 "Is this me" checks use the set of local node numbers: `isFromSelf` in text ingest done (`35a0936c`, `MeshPackets.localRadioNums()`). Left: `ChannelMessageRow`, `UserMessageRow` (Phase 6, T086), beacons.
- [X] T048 Notifications: once per `messageKey`; none for messages from the user's own radios — commit `35a0936c`, verified: `MultiRadioIngestTests`.
- [X] T049 Reception retention pruning (30 days or 50k rows): background pass (`3579188b`) and the periodic save cap, doubled in the foreground (`10b6cba4`).
- [-] T050 Replay test through the real dispatch. Moved to T067: it needs two live sessions. The ingest halves are covered by `MultiRadioIngestTests`.

**Checkpoint**: with one radio, results are the same as before; the replay test passes.

## Phase 5: Several sessions at once

- [~] T060 `RadioSessionManager`: sessions dictionary, focus, cap of 4, facade forwards to the focused session. — first step in `40605d38`: the focused radio keeps `activeConnection` and the full flow; additional radios are `AdditionalRadio` sessions (`AccessoryManager+AdditionalRadios.swift`). A full `RadioSessionManager` that also owns the focused radio comes with focus switching without reconnecting (T082).
- [X] T061 `BLETransport`: per-peripheral connect continuations and active connections; route delegate callbacks by identifier; stop pausing the scan for the whole handshake. — commit `40605d38`, verified: `MultiRadioBLETransportTests`.
- [ ] T062 BLE restoration for every restored peripheral.
- [X] T063 Discovery keeps running while connected; auto-connect uses the set of radios in `MyInfoEntity.autoConnect`. — discovery runs while connected on the Connect tab without changing the connection state (`40605d38`). Additional radios reconnect after a drop (`adfaad63`). Remembered radios (`autoConnect`, set when an additional radio connects, cleared when the user disconnects it) come back after the focused radio connects, and automatic connects are bounded to 20 s with CoreBluetooth's pending connect cancelled (`5754e69b`). Verified: `MultiRadioLifecycleTests`.
- [X] T064 A global handshake gate: one config and node-DB dump at a time across sessions. — commit `5754e69b` (`HandshakeGate`; the ingest-actor recycle also waits; `disconnect()` cancels a connect still waiting at the gate). Verified: `MultiRadioLifecycleTests`.
- [X] T065 Per-session firmware gate, lockdown and OTA scope. — commit `a32319ad` (`AccessoryManager+AdditionalRadioGates.swift`): a locked additional radio gets the passphrase saved for its peripheral once; after an unlock its waiting want-config is re-sent; no usable passphrase, or firmware below `minimumVersion`, fails its connect with `AdditionalRadioNeedsFocusError` (shown on the Connect tab, not retried). `LockdownCoordinator` and the update gate stay the focused radio's. OTA: the focused radio's OTA already pauses additional reconnects (they need a focused radio) and the focus handover. Verified: `MultiRadioLockdownTests`.
- [~] T066 Remove `switchToDevice`, `backupCurrentAndRestoreDatabase`, `defensiveResetIfForeignDatabase` and `isSwitchingDevices`. — commit `40605d38`: the foreign-store reset is now renumber-only (`renumberIfSameRadio`), and `switchToDevice` no longer backs up, clears or restores. T030 landed in `6a050ce5`; left: remove the now unused switch-era helpers (`backupCurrentAndRestoreDatabase` and friends) after the two-radio test confirms nothing still needs them.
- [~] T067 Tests: several mock sessions; BLE continuation routing with a fake central. — `MultiRadioSessionTests` and `MultiRadioBLETransportTests` (`40605d38`). Left: the two-stream replay through the real dispatch (was T050).

**Checkpoint**: two TCP radios, or a mock pair, stay connected and ingest into one store.

## Phase 6: UI

- [X] T080 Connect dialog (D-05) plus the "Connecting another radio" setting. — commit `40605d38`: confirmation dialog on tap plus Settings › App Settings › Connecting Another Radio (Ask / Keep Both / Switch). "Remember my choice" is the setting rather than a checkbox in the dialog.
- [X] T081 Connect tab: "Connected Radios" section (state, signal, battery, unread, disconnect, focus); Available Radios always shown. — "Also Connected" (focus, disconnect) and "Add a Radio" while connected (`40605d38`); battery, BLE signal and unread direct messages in each row (`d08fde38`).
- [~] T082 Radio switcher in the `ConnectedDevice` toolbar indicator and on iPad/Mac sidebars. — toolbar indicator in `bca4ecef` (`RadioSwitcherMenu`: "+N" badge and a focus menu with more than one radio). Left: a sidebar entry on iPad/Mac.
- [X] T083 Channel list grouped by `channelKey` with radio badges. — commit `df9649f9`: `ChannelMessageQuery` groups a channel's timeline (and its unread badge) by key across radios, plus the radio's own slot rows; one radio keeps the slot query. Radio badges are the "Via" labels. Verified: `ChannelMessageQueryTests`. The channel list itself is still the focused radio's channels.
- [X] T084 Composer "via" control (D-13). The pre-DM contact refresh and auto-favorite go through the sending radio (`da10664f`). — send path in `2f5dcf6a` (`sendMessage(…, viaRadio:)`, `send(_:via:)`, `resendMessage` through the sending radio); DMs pick the radio with the conversation's "Via" picker (`2f5dcf6a`); channels pick among connected radios that have the channel, each in its own slot (`df9649f9`, `TextMessageField(viaChannel:)`).
- [X] T085 DM list grouped or filtered by local radio; DM conversation query per report §13.4. — commit `2f5dcf6a`: `DirectMessageQuery` (per-radio thread by `localNodeNum`; unfiltered with one radio) and the "Via" segmented picker in `UserMessageList` (unread per radio, Offline radios readable but not writable). Verified: `DirectMessageQueryTests`, `MultiRadioConnectLifecycleTests`. The contact list itself is still one row per node.
- [X] T086 "Mine" bubbles labelled with the radio when more than one is configured. — commit `d08fde38` ("via B" on your channel messages; DM threads are already one radio each).
- [X] T087 Node list and map "heard by" filter. — commit `ec1437de`: "Heard By" picker in the node, map and contact filters (shown with more than one radio), `NodeFilterParameters.heardByRadio` persisted, matched from `NodeObservationEntity`; a radio no longer known doesn't filter. Verified: `NodeHeardByFilterTests`.
- [X] T088 Node detail per-radio table; favorite/ignore per D-11. — commit `2af545de`: `NodeHeardBySection` (hops, SNR/RSSI, last heard per radio); favorite and ignore go to every connected radio through its own connection (`setFavorite`, `setIgnored`, `sendLocalAdmin`). The per-radio override from D-11 isn't built.
- [~] T089 Settings shows which radio it configures; remote admin shows the relaying radio. — `bca4ecef` (`OtherRadiosSettingsNote` under Configure). Left: remote admin always relays through the focused radio; showing or choosing the relaying radio needs admin sends on sessions (T060).
- [X] T090 Per-radio unread badges; the app icon badge is the sum. — per-radio unread in the Connect rows (`d08fde38`) and the DM "Via" picker (`2f5dcf6a`); the Messages badge's quick updates total every radio (`2d7ab3fa`); the full recount already did.
- [X] T091 Notifications name the radio; deep links take `radio=`, handled in `Router` and `NavigationState`. — subtitle "on <radio>" (`bca4ecef`); Messages notification links carry `&radio=` with more than one radio, `Router.messagesRadio` holds it (kept out of `MessagesNavigationState` so its matches don't change), the DM thread opens on that radio, and a channel link maps the radio's slot to the focused radio's by `channelKey`. Verified: `RouterRadioDeepLinkTests`, `MultiRadioIngestTests`.
- [~] T092 Snapshot tests for the new views (`<ViewName>SnapshotTests`). — `42663087`: `AdditionalRadioRowSnapshotTests` (connected row, `forDocs: true`, referenced in bluetooth.md). Left: the Via picker, Heard By and the connect dialog.

## Phase 7: Services

- [X] T100 MQTT proxy per session. — commit `8849b76f`: `AdditionalRadioMqttBridge` (own `MqttClientProxyManager` instance, broker client and forward gate per additional radio, from its own config and channels); shared packet handling in `MqttProxyPackets`. The focused radio keeps `MqttClientProxyManager.shared` (T017 as planned isn't needed). Verified: `MqttProxyPacketsTests`, `AdditionalRadioMqttTests`.
- [X] T101 Phone position per session. — the location loop shares the phone position with every connected radio on its own connection; `sendPosition(…, viaRadio:)`, and the composer position share goes through the message's radio and slot. Not unit tested (needs a phone location); check on hardware.
- [ ] T102 Radio picker setting for TAK, CarPlay & Siri, and Watch (D-12).
- [ ] T103 TAK bridge uses the chosen radio.
- [ ] T104 CarPlay and App Intents use the chosen radio; add an optional `radio` intent parameter.
- [ ] T105 Watch uses the chosen radio.
- [ ] T106 Messages extension snapshot for the chosen radio.
- [ ] T107 Datadog: attach radio attributes to each event instead of setting them globally.

## Phase 8: Clean-up and guard rails

- [ ] T110 SwiftLint custom rule banning `preferredPeripheralNum`, `preferredPeripheralId` and `UserDefaults.firmwareVersion` outside the migration code.
- [ ] T111 Remove unused single-radio code paths and comments that describe the old switch flow.

## Phase 9: Docs

- [ ] T120 User docs listed in plan.md, with screenshots from the snapshot tests (`forDocs: true`).
- [ ] T121 Developer docs listed in plan.md.
- [ ] T122 Regenerate bundled docs and copy snapshots.

## Phase 10: Hardening

- [ ] T130 Four BLE radios for 24 hours (device checklist in `HANDOFF.md`).
- [ ] T131 BLE + TCP mix; background and foreground cycles; restoration after the app is killed.
- [ ] T132 Memory and main-actor load under four sessions (`PerformanceSeedData` and a replay).
- [ ] T133 Upgrade test with a real long-lived store (side-by-side build seeded from the owner's backup).
- [ ] T134 Full test suite, SwiftLint, XcodeGen drift check.
- [ ] T135 PR description (Summary / What changed / Testing), with screenshots.
