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
  local only). Next up: Phase 2 (session extraction).
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

- `MeshtasticSchemaV1` lists the live model types. Changing any `@Model` changes V1. Freeze V1 first (T021).
- `MessageEntity.messageId` is `@Attribute(.unique)`. Code elsewhere relies on the constraint
  merging a sent message with its mesh echo across contexts (see `MessageEntity.deduplicatedByMessageId`).
  Keep an equivalent when uniqueness moves to `messageKey`.
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
