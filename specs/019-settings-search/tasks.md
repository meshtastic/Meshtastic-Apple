# Tasks: Settings Search

**Feature**: 019-settings-search | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

The upstream half is done and approved — [protobufs#952](https://github.com/meshtastic/protobufs/pull/952)
for the mechanism and [#1081](https://github.com/meshtastic/protobufs/pull/1081) for 155 field
and 122 enum-value annotations. Nothing in this repository has changed yet beyond the spec and
`scripts/protobuf-seeding/`.

## Format: `[ID] [P?] [Story] Description`

`[P]` marks tasks that touch different files and can run in parallel.

## Phase to pull request mapping

The plan's three pull requests map onto the phases below. Keep them apart — each is reviewable
alone, and the first two are useful whether or not search ships.

| PR | Phases |
|---|---|
| [#2489](https://github.com/meshtastic/Meshtastic-Apple/pull/2489) String catalog migration (FR-016) | Phase 1 |
| [#2491](https://github.com/meshtastic/Meshtastic-Apple/pull/2491) Settings search | Phases 2–5 |

Phases 2 and 3 are one pull request, not two: search cannot stand without the registry, and
stacked pull requests are not used here.

---

## Phase 1: String catalog migration (PR 1) — [#2489](https://github.com/meshtastic/Meshtastic-Apple/pull/2489)

Independently valuable: these strings are untranslated today whether or not search ships. Must
land first, because search indexes them.

- [X] T001 Change `pickerLabel` from `String` to `LocalizedStringKey` in `Meshtastic/Views/Settings/UpdateIntervalPicker.swift` (the stored property and the memberwise init). All 19 call sites pass literals and need no edit; `Picker(pickerLabel, …)` then binds the localizing overload.
- [X] T002 [P] Convert `"X".localized` → `String(localized: "X", comment: …)` across the app-only enums in `Meshtastic/Enums/` — `IntervalEnums.swift`, `RouteEnums.swift`, `RoutingError.swift`, `SupportLevel.swift`, `KeyBackupStatus.swift`, `FirmwareEditionEnum.swift`, `MessagingEnums.swift`, `TelemetryEnums.swift`, `LayoutEnums.swift`, `ChannelRoles.swift`, `AppSettingsEnums.swift`. 192 sites; the return type stays `String` so no call site changes.
- [X] T003 [P] Fix the two adjacent bugs in `Meshtastic/Enums/DisplayEnums.swift`: `ScreenUnits.description` returns bare `"Metric"`/`"Imperial"` with no localization at all, and line 88 returns `"off".localized.capitalized` where the catalog key is `"Off"` and `.capitalized` is wrong for several locales.
- [X] T004 Split the four keys that collide across senses, using explicit keys with `defaultValue:` — `Cancel` in `Meshtastic/Enums/CannedMessagesConfigEnums.swift` (keypad key vs dismiss verb), `All` in `Meshtastic/Enums/DeviceEnums.swift` (rebroadcast mode vs log filter vs VoiceOver hop limit), `Default` in `Meshtastic/Enums/SerialConfigEnums.swift` (baud rate vs log level vs app icon vs no-channel), and generalize the `Standard` comment in `Localizable.xcstrings`, which is offline-map-download specific.
- [X] T005 Handle the two non-literal receivers that cannot be converted mechanically: `MapLayer` and `OverlayType` in `Meshtastic/Enums/AppSettingsEnums.swift` both do `self.rawValue.localized`, which the extractor cannot see. Replace with a `switch` over the cases.
- [ ] T006 (blocked on the Xcode GUI — `xcodebuild` emits `.stringsdata` but does not write back) Build once in Xcode so the extractor writes the new keys into `Localizable.xcstrings`, then verify the diff is **purely additive** before committing. There is no headless path; the file is 3.1 MB and 1842 keys, and a rebuild that reorders or prunes produces an unreviewable diff.

**Checkpoint**: new keys present in the catalog, no existing key removed or reordered, app builds.

---

## Phase 2: Field-metadata wiring (PR 2) — [#2491](https://github.com/meshtastic/Meshtastic-Apple/pull/2491)

Blocking prerequisite for every user story — nothing can be indexed until the registry exists.

- [X] T007 Bump the `protobufs` submodule to a commit carrying `field_metadata.proto` and the annotations, once #952 and #1081 merge. Until then, check out #1081's branch locally and use `scripts/gen_protos.sh --no-pull`, which skips the reset to `origin/master`.
- [X] T008 Add a fourth phase to `scripts/gen_protos.sh` after the existing `protoc` call: build `protoc-gen-fieldmeta-swift` from `protobufs/tools/`, then run it with `--fieldmeta-swift_out=./Meshtastic/Model`. A separate invocation, not a second `--*_out` on the existing one — the output directory differs. Note in a comment that this plugin is pinned by submodule SHA, unlike `protoc-gen-swift` which is pinned via `MeshtasticProtobufs/Package.resolved`.
- [X] T009 Generate `Meshtastic/Model/FieldMetadataRegistry.swift` and commit it. It must go in the **app target**, not `MeshtasticProtobufs` — `SWIFT_EMIT_LOC_STRINGS` is per-target and a SwiftPM package has neither it nor a catalog, so a registry there would compile fine and resolve to English forever.
- [X] T010 [P] Exclude the generated registry in both `.swiftlint.yml` and `.swiftlint-precommit.yml`. The app target is linted and the generated literals exceed the 400-character line limit; this extends the existing `MeshtasticProtobufs` precedent rather than disabling a rule (plan Constitution Check VI).
- [X] T011 [P] Add `submodules: recursive` to the checkout in `.github/workflows/unit-tests.yml`. Without it `protobufs/` is empty on every runner and T024's completeness test takes its soft-skip and proves nothing.
- [X] T012 [P] Add `protobufs` to the `paths:` filter in `.github/workflows/xcodegen-drift.yml`, so a pull request that bumps only the submodule triggers something.
- [X] T013 Build in Xcode and confirm the registry's `String(localized:)` calls land in `Localizable.xcstrings`. If they do not, the file is in the wrong target — this is the failure mode that is otherwise silent.
- [ ] T014 (deferred: cleanup, not a prerequisite for search) Replace the string properties on the 13 proto-backed app enums with registry lookups — `DeviceEnums.swift`, `LoraConfigEnums.swift`, `DisplayEnums.swift`, `PositionConfigEnums.swift`, `SerialConfigEnums.swift`, `CannedMessagesConfigEnums.swift`, `BluetoothModes.swift`. For example `DeviceRoles.name` becomes `Config.DeviceConfig.Role(rawValue: rawValue)?.metadata?.label ?? ""`. Keep each enum's ordering, icons and `protoEnumValue()` — only the strings move.
- [ ] T015 (deferred with T014) Collapse `DeviceRoles.isDeprecated` (`DeviceEnums.swift:34`) and `ModemPresets.isDeprecated` onto the registry's mirrored `deprecated` attribute, removing the hand-maintained lists.
- [ ] T016 Verify in a non-English locale that the 127 proto-backed enum strings still render translated after T014, and that the 37 region names — previously English for everyone — now translate.

**Checkpoint**: registry generated, committed and extracted; proto-backed enums read from it; lint and CI green.

---

## Phase 3: US1 — find a setting without knowing its screen (P1) 🎯 MVP — in [#2491](https://github.com/meshtastic/Meshtastic-Apple/pull/2491)

**Independent test**: type "hops" in Settings and get the LoRa `Number of hops` control with its
screen and section; tapping it opens LoRa.

- [X] T017 [P] [US1] Define `SettingsSearchEntry`, `FieldIdentity`, `SettingsListSection` and `Visibility` in `Meshtastic/Model/Search/SettingsSearchEntry.swift` per [data-model.md](./data-model.md). Identity is destination plus label, never label alone — "Enabled" labels six controls.
- [X] T018 [P] [US1] Add `CaseIterable` to `SettingsNavigationState` in `Meshtastic/Router/NavigationState.swift` so the drift test can enumerate destinations instead of diffing against the hand-lists in `NavigationStateTests.swift`.
- [X] T019 [US1] Build the registry-backed half of the index in `Meshtastic/Model/Search/SettingsSearchIndex.swift`: walk the config messages, resolve each field through `FieldMetadataRegistry`, and map it to a `SettingsNavigationState`. Keywords arrive as one `|`-delimited string — split and trim.
- [X] T020 [US1] Write the curated app-level catalogue in `Meshtastic/Model/Search/SettingsSearchCatalogue.swift` — roughly 68 controls with `String(localized:)` text and `field: nil` (FR-008a). One file, not declarations beside each view.
- [X] T021 [US1] Implement matching and ranking in `Meshtastic/Model/Search/SettingsSearchEngine.swift`: `localizedStandardContains` for matching (not `lowercased().contains`, which is not diacritic-safe), field-weighted scoring — exact label, label prefix, keyword, then description or option value — with ties broken by section order then label so the order is fully determined.
- [X] T022 [US1] Add `.searchable(text:placement:.navigationBarDrawer(displayMode: .always), prompt:)` to `Meshtastic/Views/Settings/Settings.swift` and render filtered sections in place of the full list while the query is non-empty. `DocBrowserView.swift:69-94` is the working precedent for filtering a static catalogue and dropping empty sections.
- [X] T023 [US1] Build the result row in `Meshtastic/Views/Settings/SettingsSearchResultsView.swift` — label, screen and section breadcrumb, navigating via `Router.settingsPath`. 44×44 minimum target, legible at the largest Dynamic Type size (FR-014).
- [X] T024 [US1] Write the completeness test in `MeshtasticTests/SettingsSearchIndexTests.swift`: parse `protobufs/meshtastic/config.proto` and `module_config.proto` and assert each of the 221 fields is either indexed or on the FR-015a exemption list of 16 with its group named. Use the `SnapshotReferenceStore.swift:35-65` pattern — pure parse logic taking the URL as a parameter, `#filePath` injected at the edge.
- [X] T025 [US1] Write the drift test in `MeshtasticTests/SettingsSearchIndexTests.swift`: every entry's label occurs as a string literal in the view file for its screen, and every destination is a real `SettingsNavigationState` case. Demonstrate it fails by renaming a label before reverting (SC-003).
- [X] T026 [US1] Pin a per-screen entry count in `MeshtasticTests/SettingsSearchIndexTests.swift`, so a control added to a form without an index entry fails rather than going quietly unsearchable.
- [X] T027 [P] [US1] Write `MeshtasticTests/SettingsSearchEngineTests.swift`: ranking order, deterministic tiebreak, and `localizedStandardContains` behaviour (`resume` matches `résumé`, case ignored).
- [X] T028 [US1] Start the SC-002 query corpus in `MeshtasticTests/SettingsSearchEngineTests.swift` — "hops", "psk", "duty cycle", "Long Fast", "transmit power", "color" — each asserted to return its intended control among the top results. This replaces the per-entry keyword assertion; grow it whenever a search that should have worked did not.

**Checkpoint**: US1 is shippable on its own. Documentation results and disconnected handling are additive.

---

## Phase 4: US2 — search reaches the documentation (P2) — in [#2491](https://github.com/meshtastic/Meshtastic-Apple/pull/2491)

**Independent test**: search a term appearing in both a setting and a doc page; both appear under
distinct section headings.

- [X] T029 [US2] Index the 31 bundled pages from `Meshtastic/Resources/docs/index.json`, which already carries `{id, title, section, navOrder, keywords}` and is generated by `scripts/build-docs.sh`, so it cannot drift.
- [X] T030 [US2] Render doc results in `Meshtastic/Views/Settings/SettingsSearchResultsView.swift` under their own "Help & Documentation" section below the settings results, never dimmed — documentation reads the same with or without a radio. Empty sections must not render.
- [X] T031 [US2] Open the selected page in the existing browser at `Meshtastic/Views/Settings/HelpAndDocumentation/DocBrowserView.swift`, routed through `Router` like any other destination.

---

## Phase 5: US3 — discover a feature while disconnected (P3) — visibility rules in [#2491](https://github.com/meshtastic/Meshtastic-Apple/pull/2491)

**Independent test**: with no radio connected, search a radio-configuration term and see the result
listed, de-emphasised, with an explanation.

- [X] T032 [US3] Compute `Visibility` per query in `Meshtastic/Model/Search/SettingsSearchEngine.swift` from connection and node state: `.deEmphasised` when a radio is needed and none is connected (FR-012), and for `admin_only` fields (FR-012b).
- [X] T033 [US3] Hide `diy_only` results unless the connected hardware model is `DIY`-tagged in `DeviceHardware.json` — six models carry it. Show them when disconnected, since the hardware is unknown (FR-012a).
- [X] T034 [US3] Show deprecated entries de-emphasised and labelled as deprecated rather than hidden (FR-012c). The earlier "hide unless the radio holds that value" rule needed per-field node state the index does not carry and hid the setting a user was searching for; see the clarification in spec.md.
- [ ] T035 [US3] Confirm a dimmed result still navigates, landing on the screen's existing "Please connect to a radio" state from `ConfigHeader.swift:33-35` rather than an error.

---

## Phase 6: Polish

- [ ] T036 [P] Verify every result label, section and option value renders translated in a non-English locale, and that the `Localizable.xcstrings` diff from this work is additive (SC-004).
- [ ] T037 [P] Check Dynamic Type at 200% and VoiceOver on result rows, per design standards §5.
- [ ] T038 [P] Confirm parity on iPad and Mac Catalyst. The TV target has its own `SettingsView.swift` and is out of scope.
- [ ] T039 Re-run `MeshtasticTests/SettingsSearchIndexTests.swift` against a fresh submodule bump to confirm it still fails when a field is added without an entry.

---

## Dependencies

- **Phase 1** is independent and can start now. It does not block Phase 2.
- **Phase 2** blocks all user stories: no registry, no index. T007 blocks everything in the phase.
- **Phase 3 (US1)** depends on Phase 2. Within it: T017 and T018 are parallel; T019 and T020 both feed T021; T022 and T023 need T021; tests T024–T028 need the index to exist.
- **Phase 4 (US2)** depends only on the UI shell from T022, not on Phase 3's tests.
- **Phase 5 (US3)** depends on T017's `Visibility` and the result row from T023.
- **Phase 6** last.

## Parallel opportunities

- Phase 1: T002, T003 and the T004 key splits touch different enum files.
- Phase 2: T010, T011 and T012 are three separate config files.
- Phase 3: T017 ∥ T018, and T027 ∥ the T024–T026 index tests.
- Phase 6: T036, T037 and T038 are independent checks.

## Implementation strategy

Ship Phase 1 on its own — 192 untranslated strings is worth fixing regardless. Phase 2 next, which
makes the registry real and lets the enums stop carrying English. Then US1 alone is a usable
feature; US2 and US3 are each a small addition on top and can land separately.
