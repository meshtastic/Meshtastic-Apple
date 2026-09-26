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
  `40605d38`; see tasks.md for the partial ones.
- Mesh Multi (`~/Applications/Mesh Multi.app`, side-by-side, own container) was rebuilt from
  `adfaad63` (adds reconnect of additional radios) and is ready for the first two-radio test
  below. Not yet run by anyone.
- Next up: the owner's two-radio test; then BLE restoration (T062), the handshake gate (T064),
  and auto-connect of remembered radios at launch. T030 (merge old backups) before release.
- Baseline and latest: the full suite passes in the iOS Simulator (3,326 Swift Testing tests plus
  29 XCTests, about 35–45 seconds of test time).

## First two-radio test (Mesh Multi, Mac)

1. Open Mesh Multi, connect radio A from Available Radios (normal first connect).
2. On the Connect tab, "Add a Radio" lists radio B. Tap it; choose "Keep A and Add B".
3. B shows under "Also Connected", Connecting… then Connected. Log lines start with `🔗➕`.
4. Send a channel message from a third device: it appears once. Nodes heard by both radios
   appear once; the node list shows the best hops.
5. ⋯ → Disconnect on B: A stays connected. Re-add B. ⋯ → Focus This Radio on B: A disconnects,
   B reconnects as focused, and nothing is wiped (messages and nodes from A remain).
6. Settings › App Settings › Connecting Another Radio: try Keep Both / Switch.
7. Power-cycle B while both are connected: it should drop from "Also Connected" and come back
   on its own (`🔗🔁` log lines). A disconnects nothing.
8. Worth watching: memory and CPU with two node dumps; any "Dropping an event from a
   disconnected additional radio" spam; whether BLE scanning while connected upsets pairing.
- Small pull requests, ready for the owner to push (each is one commit on `origin/main`):
  - `fix/restore-dropped-backup-fields` — the restore fix and its tests.
  - `chore/sync-string-catalog` — the string catalog sync.
  The same two commits stay at the bottom of this branch; after they merge upstream,
  `git rebase origin/main` drops them.

## In progress

_Nothing. When you start a task, mark it `[~]` in tasks.md and note it here._

## Blocked / waiting on the owner

- Real-radio testing: the owner is preparing two more radios and will test on the Mac when ready.

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
- String catalog: when a build changes `Localizable.xcstrings`, run
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
  `processFromRadio`, `connect(to:)` and `upsertNodeInfoPacket`. These warnings predate this
  work, and the feature's changes add at most four lines to each. Splitting them up is part of T060.
- `MeshtasticSchemaV1` lists the live model types, and that is intended (D-16): every release since
  2.7.13 has changed them additively.
- `MessageEntity.messageId` is no longer unique (`10b6cba4`); `messageKey` ("sender:packetId")
  is. Both insert paths (ingest, `sendMessage`) set it, so a sent message and its echo still merge.
  Anything that looks a message up by `messageId` alone (ACKs, `adminResponseAck`, tapback
  replies) can in rare cases match another sender's message; the lists already dedupe by id
  before building `Dictionary(uniqueKeysWithValues:)`, which would otherwise trap.
- SwiftData `fetch` does not see unsaved inserts. The new lookups (`receptions`,
  `observations(ofNode:)`) also scan `modelContext.insertedModelsArray`, like `findOrCreateNode`.
- Single-radio behaviour is kept on purpose: with one observation, `updateAnyPacketFrom` writes
  the node exactly as before and only mirrors into the observation. Aggregation starts with a
  second observation. Keep it that way; the owner's always-on radio must see no change.
- The backfill attributes old rows to `UserDefaults.preferredPeripheralNum`, which is the store's
  owner only while the switch flow exists. When T066 removes switching, run the backfill for
  each store before it is merged (T030), not after.
- Additional radios must never reach the focused radio's handlers for anything but mesh
  packets: `handleMyInfo` writes the preferred radio, `handleConfig` sends a timezone to the
  focused radio, `handleModuleConfig` sends admin requests through it, and the `.error` /
  `.disconnected` branches of `didReceive` close the focused connection. Route through
  `processAdditionalFromRadio`.
- `MeshPackets.recreateShared()` (connect Step 7 and every `ingestRecycleInterval` packets)
  invalidates the old actor; an additional radio's handler that captured it mid-write loses
  that write. Rare, but a candidate for the 24-hour test's "missing packet" findings.
- Discovery while connected must not call `updateState(.discovering)`; `startDiscovery` only
  does that with no focused radio now.
- `SchemaHistoryUpgradeTests.fixtureInventoryCoversEverySwiftDataRelease` sometimes fails with a
  SQLite disk I/O error reading the bundled fixture's metadata. It predates this work and passes
  on a re-run.
- The restore importer copies fields by hand. Every new stored attribute must be added to
  `NodeBackupManager+Import.swift` (`NodeBackupRestoreFieldTests` shows the pattern).
- A BLE radio serves one phone connection at a time. The released app and the side-by-side
  build must not both target the same radio.

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
