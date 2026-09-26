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

- [ ] T010 Add `RadioSession` (`Meshtastic/Accessory/Radio Session/RadioSession.swift`) holding all per-connection state now on `AccessoryManager`: device/connection, state flags, `connectionStepper`, event task, heartbeats, config-refresh owner, DB gate, first-NodeInfo continuation, lockdown, firmware gate, OTA flag, counters, `expectedNodeDBSize`, region presets, firmware edition.
- [ ] T011 `AccessoryManager` holds `session: RadioSession?`. Its old properties become computed forwarders, so views compile unchanged.
- [ ] T012 Pass the session explicitly: `didReceive` → `processFromRadio` → every `handle*`. Remove `activeConnection?.device.num` reads inside handlers.
- [ ] T013 [P] Move the connect steps (`AccessoryManager+Connect.swift`) onto the session.
- [ ] T014 [P] Move the ToRadio builders onto the session (`RadioSession+ToRadio.swift`), with facade forwarders.
- [ ] T015 [P] Add `TransportDelegate`; remove `AccessoryManager.shared` from `BLETransport` restoration and `TCPTransport.manuallyConnect`.
- [ ] T016 [P] Replace `UserDefaults.preferredPeripheralNum` reads in ingest and services (`UpdateSwiftData.swift`, `AccessoryManager.swift:1472`, `DiscoveryScanEngine`) with the session's node number.
- [ ] T017 [P] Make `MqttClientProxyManager` an instance per session, with a per-instance forward gate.
- [ ] T018 [P] Version gates read `session.firmwareVersion`; remove `UserDefaults.firmwareVersion` reads.
- [ ] T019 Unit tests: session lifecycle with a mock `Connection`; facade forwarding.

**Checkpoint**: all tests pass; the app behaves exactly as before with one radio.

## Phase 3: Schema V2

- [ ] T020 Spike: confirm the two-stage `messageKey` uniqueness migration (plan.md Schema V2 item 2) on a scratch store; record the result in `HANDOFF.md`.
- [ ] T021 Freeze V1: nested snapshot copies of all V1 models under `MeshtasticSchemaV1`. `SchemaHistoryUpgradeTests` must still pass unchanged.
- [ ] T022 Add `MeshtasticSchemaV1_1` (new columns, not yet unique) and `MeshtasticSchemaV2` (`messageKey` unique), and point the live model types at V2.
- [ ] T023 Add `NodeObservationEntity` and `PacketReceptionEntity`.
- [ ] T024 Add the new attributes (plan.md Schema V2 item 5).
- [ ] T025 Custom stage V1 → V1_1 with the `didMigrate` backfill (plan.md Schema V2 item 7).
- [ ] T026 Lightweight stage V1_1 → V2.
- [ ] T027 `channelKey` derivation (`ChannelEntity+Key.swift`) plus tests for: the default channel, custom channels, the same name with a different PSK, and different presets on an unnamed primary.
- [ ] T028 Update the backup importer (`NodeBackupManager+Import.swift`) for the new entities and attributes.
- [ ] T029 Migration tests: every fixture in `research/schema-history` opens as V2 with the backfill correct.
- [ ] T030 Backup merge job (D-09): resumable, keyed merge, originals kept. Tests use two synthetic radio backups.

**Checkpoint**: an existing store and its backups upgrade with nothing lost; the app still runs with one radio.

## Phase 4: Ingest scoping and de-duplication

- [ ] T040 Every `MeshPackets` entry point takes `radioNum`.
- [ ] T041 Receptions: upsert `(radioNum, from, id)`; run the handler only for new packets.
- [ ] T042 Observations: upsert per `(radioNum, from)` on every packet and in the node-DB dump; recompute aggregates in one function.
- [ ] T043 Text messages: set `fromNum`, `toNum`, `localNodeNum`, `channelKey`, `messageKey`; de-duplicate by `messageKey`.
- [ ] T044 [P] Positions and telemetry: de-duplicate by `(node, packetId)`.
- [ ] T045 [P] Admin sessions: read and write passkeys on the observation for the relaying radio.
- [ ] T046 [P] Trace routes: originator is the sending local radio.
- [ ] T047 "Is this me" checks use the set of local node numbers (`ChannelMessageRow`, `UserMessageRow`, the self-packet drop, `isFromSelf`, beacons).
- [ ] T048 Notifications: once per `messageKey`; none for broadcasts from the user's own radios.
- [ ] T049 Reception retention pruning (30 days or 50k rows).
- [ ] T050 Replay test: two captured radio streams into one store; assert de-duplication, scoping and aggregates.

**Checkpoint**: with one radio, results are the same as before; the replay test passes.

## Phase 5: Several sessions at once

- [ ] T060 `RadioSessionManager`: sessions dictionary, focus, cap of 4, facade forwards to the focused session.
- [ ] T061 `BLETransport`: per-peripheral connect continuations and active connections; route delegate callbacks by identifier; stop pausing the scan for the whole handshake.
- [ ] T062 BLE restoration for every restored peripheral.
- [ ] T063 Discovery keeps running while connected; auto-connect uses the set of radios in `MyInfoEntity.autoConnect`.
- [ ] T064 A global handshake gate: one config and node-DB dump at a time across sessions.
- [ ] T065 Per-session firmware gate, lockdown and OTA scope.
- [ ] T066 Remove `switchToDevice`, `backupCurrentAndRestoreDatabase`, `defensiveResetIfForeignDatabase` and `isSwitchingDevices`.
- [ ] T067 Tests: several mock sessions; BLE continuation routing with a fake central.

**Checkpoint**: two TCP radios, or a mock pair, stay connected and ingest into one store.

## Phase 6: UI

- [ ] T080 Connect dialog (D-05) plus the "Connecting another radio" setting.
- [ ] T081 Connect tab: "Connected Radios" section (state, signal, battery, unread, disconnect, focus); Available Radios always shown.
- [ ] T082 Radio switcher in the `ConnectedDevice` toolbar indicator and on iPad/Mac sidebars.
- [ ] T083 Channel list grouped by `channelKey` with radio badges.
- [ ] T084 Composer "via" control (D-13).
- [ ] T085 DM list grouped or filtered by local radio; DM conversation query per report §13.4.
- [ ] T086 "Mine" bubbles labelled with the radio when more than one is configured.
- [ ] T087 Node list and map "heard by" filter.
- [ ] T088 Node detail per-radio table; favorite/ignore per D-11.
- [ ] T089 Settings shows which radio it configures; remote admin shows the relaying radio.
- [ ] T090 Per-radio unread badges; the app icon badge is the sum.
- [ ] T091 Notifications name the radio; deep links take `radio=`, handled in `Router` and `NavigationState`.
- [ ] T092 Snapshot tests for the new views (`<ViewName>SnapshotTests`).

## Phase 7: Services

- [ ] T100 MQTT proxy per session.
- [ ] T101 Phone position per session.
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
