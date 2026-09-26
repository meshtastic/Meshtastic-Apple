# Handoff: Multiple Radios Connected at Once

Read this first if you are picking the work up. Update it in the same commit as the work.

**Feature**: 021-multi-radio-connections | [spec.md](./spec.md) · [plan.md](./plan.md) · [tasks.md](./tasks.md)

## Current state

- Branch `feature/multi-radio`, based on `origin/main` `ed36762c` (2026-09-25). Not pushed; the owner pushes.
- Commits below the feature work, carried into the branch:
  - `15baebb0` Keep every stored field when restoring a radio's backup (fix + tests)
  - `67fba963` Sync the string catalog with the current source
  - `d913970a`, `230eda8c` Research report and recommendation
- Done: tracking docs. Next up: T003 (blocked on the owner), then Phase 2 (session extraction).
- Nothing in the app has changed yet for this feature.

## In progress

_Nothing. When you start a task, mark it `[~]` in tasks.md and note it here._

## Blocked / waiting on the owner

- T003 side-by-side build: which app holds the long-lived data (App Store/TestFlight or an
  Xcode build), which signing team is used, and whether the side-by-side scheme goes in the PR.
- Whether the standalone restore fix and the catalog sync should go in their own pull requests (`CLAUDE.md` rule).

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
