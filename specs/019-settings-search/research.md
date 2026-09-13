# Research: Settings Search

**Feature**: 019-settings-search | **Date**: 2026-09-13

Phase 0 findings. Each decision below resolves an unknown left open by the spec or
the clarification session.

## D1. The whole index comes from the protobufs, including the display strings

**Decision**: `label`, `description` and `keywords` are `(meshtastic.field_metadata)`
attributes alongside `unit`, `min_value`, `max_value`, `diy_only`, `admin_only` and
`deprecated`. The generators emit string attributes as
`String(localized:defaultValue:comment:)`, so the English in the schema is the source
string, Xcode's extractor pulls it into `Localizable.xcstrings` on build, and
translations live in the app's catalog. One source of truth for what a setting is
called, shared by every client.

**Rationale**: The generator emitting bare literals was a property of the generator, not
a constraint — and the generator is ours. Changed in
[meshtastic/protobufs#952](https://github.com/meshtastic/protobufs/pull/952) (commit
`20fadc6`, `generator-parity` green): both the Go and Swift plugins now render string
attributes as

```swift
label: String(localized: "meshtastic.Config.LoRaConfig.hop_limit.label",
              defaultValue: "Hop Limit",
              comment: "label of meshtastic.Config.LoRaConfig.hop_limit")
```

The catalog key is the field's full proto name plus the attribute, not the English. That
matters: "Enabled" labels six different controls, and a value-keyed catalog would force
one translation on all of them, which languages that inflect cannot do. Keying on the
field gives each its own entry, and sidesteps the collision problem that already affects
the hand-written strings in D6.

**Alternatives considered**:

- *Keep language app-side and take only structure from the proto.* Rejected. Two files to
  edit per setting, held together only by a test, and the English would drift from the
  schema every other client reads.
- *Emit keys from the proto and declare them in a separate catalog-visible Swift file.*
  Rejected for the same reason, with the added failure mode that a rename falls back to
  the raw key with no build error.

**Consequences**:

- The registry must be generated into the **app target**, not `MeshtasticProtobufs` — see
  D2, which this reverses.
- `keywords` is a single `|`-delimited string, because `FieldMetadata` attributes must be
  scalar and `repeated` is rejected at generation time. The app splits on `|` and trims.
  A translator sees one catalog entry per field with a comment naming the field.
- A second protobufs change carrying annotations for all 221 fields is back on the
  critical path — see D5.

## D2. The registry is generated into the app target

**Decision**: Generate `FieldMetadataRegistry.swift` into `Meshtastic/Model/`, not into
`MeshtasticProtobufs` beside the other generated protobuf code.

**Rationale**: this is forced by D1. `SWIFT_EMIT_LOC_STRINGS` is a per-target setting with
no file-level opt-out, and it is `YES` on the app target (`project.yml:355, 398`). A
SwiftPM package has neither that setting nor a string catalog, so a registry generated
into `MeshtasticProtobufs` would have its `String(localized:)` calls compile and resolve
to English forever — the strings would simply never be offered to translators.

`Meshtastic/Model/` is already a `syncedFolder` (`project.yml:200-201`) and holds
`ConfigModels.swift`, the SwiftData mirror of the same protos. Dropping a file there needs
no `project.yml` edit and no regenerated `.xcodeproj`, so `xcodegen-drift.yml` stays green.

**Cost this carries**: the app target *is* linted — `.swiftlint.yml` excludes only
`MeshtasticProtobufs` and `build` — and the generated literals run to several hundred
characters against a `line_length: 400` limit. The file needs an entry in the `excluded:`
lists of both `.swiftlint.yml` and `.swiftlint-precommit.yml`. That follows the precedent
already set for `MeshtasticProtobufs` rather than establishing a new one, and it is the
consuming app's lint policy to set, which is why it is handled here and not by teaching a
shared cross-language generator about SwiftLint.

This will also be the first generated Swift committed into the app target; there is no
existing precedent in the repo.

**Note**: the emitted `public struct FieldMetadata` has no explicit initializer, so its
memberwise init is internal to whatever module holds it. Consumers read through
`FieldMetadataRegistry.get(_:tag:)` and the per-type static accessors and never construct
one, so this does not bite.

**One detail that decides whether this works**:

- Point `--fieldmeta-swift_out` at the directory the file should land in. Unlike
  `protoc-gen-swift`, this plugin emits a bare filename
  (`generatorOutputs.add(fileName: "FieldMetadataRegistry.swift")`) with no package-path
  prefix.
- The plugin is pinned differently from `protoc-gen-swift`. `gen_protos.sh:57-64` builds
  `protoc-gen-swift` out of `MeshtasticProtobufs/Package.resolved`, so plugin and runtime
  library versions agree by construction — a deliberate guard, documented at `:12-20`,
  against Homebrew's older plugin silently downgrading output. `protoc-gen-fieldmeta-swift`
  lives in the `protobufs` submodule, so it is pinned by the submodule SHA instead. That
  asymmetry is acceptable but must be stated, because the existing pin is load-bearing
  and a reader will assume it covers both.

## D3. Two generator bugs found and fixed upstream

Adding attributes in D1 meant exercising paths #952 had never run. Both bugs were latent:
every existing annotation sets exactly one attribute, which is the only case that worked.
Fixed in `20fadc6` on `jamesarich/field-metadata`, with tests that fail without the fix.

**The Swift plugin was not schema-extensible.** `field_metadata.proto` documents that
adding an attribute is "a SCHEMA-ONLY change… No code generator or build change is
needed". That held for the Go plugin — `fieldMetadataSchema` reads the attribute list off
the extension descriptor and `main.go:316` walks values with
`m.Get(xtd).Message().Range(...)` — but not the Swift one, which rendered values in
`literal(for:shape:)` through `switch f.name` over the six known names ending in
`default: fatalError`. That loop runs over every schema field for every entry, so a
seventh attribute crashed the plugin for all fields, whether or not any set it. It now
reads values by traversing the decoded option with a `SwiftProtobuf.Visitor`, the direct
counterpart of Go's `Range`.

**Multi-attribute literals did not compile.** Both generators emitted arguments in
name-sorted order, but the `FieldMetadata` struct's properties are emitted in schema
declaration order, and Swift's memberwise initializer requires arguments in
property-declaration order. Any field setting two attributes produced code that would not
build — and the `generator-parity` job could not catch it, because both generators were
identically wrong. Both now emit in schema order.

Two smaller divergences fixed alongside: the Swift plugin mapped integer kinds to
`Int32`/`UInt32`/`UInt64` and float to `Float` where the Go plugin used `Int64` and
`Double`, so the two agreed only because bool, double and string are the only types in
use; and the Swift string escaper did not handle tabs, which the Go one did.

## D4. Completeness is checked against the `.proto` text, not the registry

**Decision**: The completeness test parses `protobufs/meshtastic/config.proto` and
`protobufs/meshtastic/module_config.proto` from disk and asserts every field is either
indexed or named on an explicit exemption list.

**Measured denominator**: **221 fields across 29 messages** — 93 in `config.proto`
(9 messages) and 128 in `module_config.proto` (20 messages). This replaces the spec's
estimated "~201 of 269".

| `config.proto` | | `module_config.proto` | |
|---|---|---|---|
| DeviceConfig | 12 | MQTTConfig | 11 |
| PositionConfig | 13 | MapReportSettings | 3 |
| PowerConfig | 9 | RemoteHardwareConfig | 3 |
| NetworkConfig | 10 | NeighborInfoConfig | 3 |
| IpV4Config | 4 | DetectionSensorConfig | 8 |
| DisplayConfig | 14 | AudioConfig | 7 |
| LoRaConfig | 20 | PaxcounterConfig | 4 |
| BluetoothConfig | 3 | TrafficManagementConfig | 5 |
| SecurityConfig | 8 | SerialConfig | 8 |
| | | ExternalNotificationConfig | 15 |
| | | StoreForwardConfig | 6 |
| | | RangeTestConfig | 4 |
| | | TelemetryConfig | 15 |
| | | CannedMessageConfig | 11 |
| | | AmbientLightingConfig | 5 |
| | | StatusMessageConfig | 1 |
| | | MeshBeaconConfig | 11 |
| | | BroadcastTarget | 3 |
| | | TAKConfig | 2 |
| | | RemoteHardwarePin | 3 |
| **Total** | **93** | **Total** | **128** |

Nine of the 221 are already marked `[deprecated = true]` upstream, leaving **212 live
fields** — which lines up with the spec's estimate of roughly 201 proto-backed controls
once the fields with no screen are removed. Two messages sit outside the count on purpose:
`Config.SessionkeyConfig` is empty, and `DeviceUIConfig` lives in a third file,
`device_ui.proto`, so surfacing device-UI settings later is additional annotation scope
rather than something this count already covers.

**Rationale**: the registry only contains fields that carry an annotation
(`where field.options.hasFieldMetadata || field.options.deprecated`), so it cannot serve
as the list of what *should* exist. The `.proto` text is the authoritative list, it is
in-tree as a submodule, and parsing it needs no build-time protobuf machinery.

**Alternatives considered**:

- *Runtime reflection over swift-protobuf's `_protobuf_nameMap`.* Rejected — it is an
  opaque bytecode string (`config.pb.swift:2425`) with no stable public iteration API.
- *Treat the registry itself as the list of what exists.* Rejected — it holds only fields
  that carry an annotation, and fields with no control are deliberately never annotated,
  so it can confirm what is there but never what is missing.

**The assertion is "accounted for", not "one entry each".** A field maps to any number of
controls, in both directions, so a strict bijection would be wrong:

- *One field, many controls.* `position_flags` is a single `uint32` bitfield behind **ten**
  independent toggles, via an `OptionSet` declared in the view itself
  (`PositionConfig.swift:12-24`), each with its own label — "Altitude", "Number of
  satellites", "Vehicle heading" and so on. `coding_rate` backs three controls
  (`LoRaConfig.swift:65-101`). `tls_enabled` renders as two different toggles depending on
  whether the default server is selected (`MQTTConfig.swift:237-248`).
- *Fields with no control at all.* `json_enabled` is deprecated and unsurfaced;
  `frequency_offset` and `override_duty_cycle` exist on `LoRaConfigEntity` but appear in no
  `@State` and no save assignment; `RemoteHardwarePin`'s three fields have no screen.
- *Read-but-never-written.* `gps_enabled` is loaded for a migration heuristic and
  deliberately never saved (`PositionConfig.swift:312-314`). Search must not offer it.

**One-to-many is the limit of what the schema can express, and it is small.** A field
carries one `label`, so it cannot name ten toggles. `position_flags`, `coding_rate` and
`tls_enabled` therefore keep curated app-side entries; the proto annotation describes the
field, and the individual controls are indexed beside it. This is an enumerated exception
of three fields out of 221, recorded on the same exemption list the completeness test
already reads, rather than a general escape hatch.

So the test asserts every field either has at least one index entry or appears on an
exemption list carrying a stated reason, and that the exemption list is the only way a
field escapes. Nine fields are already `[deprecated = true]` upstream and are exempt
automatically once #952 lands.

**Pattern to reuse**: `SnapshotReferenceStore.swift:35-65` — pure path/parse logic taking
the URL as a parameter, `#filePath` injected at the edge, with the
`guard fileExists else { return }` soft-skip from `DocBundleTests.swift:125-128` for when
the path is not readable.

**The guard is vacuous on CI today and needs a one-line fix.** `unit-tests.yml:23` checks
out with `actions/checkout@v4` and no `submodules:` key — and no workflow in the repo sets
one. `protobufs/` is therefore empty on every runner, so a `.proto`-parsing test would take
the soft-skip and pass without checking anything. The app still builds because the
generated `.pb.swift` files are committed; only regeneration needs the submodule. Adding
`submodules: recursive` to that checkout is a prerequisite for this test to mean anything.

**A second gap in the same area**: `xcodegen-drift.yml`'s `paths:` filter covers
`project.yml`, `.xcodegen-version`, `Meshtastic.xcodeproj/**` and `**/*.swift`, but not
`protobufs` or `.gitmodules`. A pull request that bumps only the submodule triggers no
workflow at all. If the registry is to be trusted, that filter needs `protobufs` too.

## D5. Upstream is on the critical path, in two steps

**Decision**: 019 depends on meshtastic/protobufs#952 for the mechanism, and on a second
protobufs change carrying the annotations for every proto-backed control. The second is
the bulk of the work and the permanent deliverable.

**Status of #952** (2026-09-13): open and mergeable. Carries the `field_metadata`
extension, the Go and Swift generators, the parity harness, and — as of `20fadc6` — the
`label`, `description` and `keywords` attributes with localized string emission, the two
generator fixes in D3, and `hop_limit` annotated as a worked example. `ascii-dash`,
`build`, `go-plugin-test` and `generator-parity` green.

**The annotation change** applies `label`, `description` and `keywords` across
`config.proto` and `module_config.proto` — roughly 201 of the 221 fields, excluding the
nine deprecated and those with no control. Branch it from #952 rather than waiting: the
app can then be built end to end against a real generated registry, and nothing is thrown
away when #952 merges and the branch rebases.

**What this costs**: unlike the previous plan, search cannot ship ahead of the
annotations — an index whose labels do not exist yet has nothing to match. The trade is
deliberate: one source of truth for what every setting is called, shared by Apple,
Android and web, instead of three hand-maintained copies.

## D6. Localization migration is its own change

**Decision**: FR-016 (the string-catalog migration) ships as a separate pull request,
before or alongside search, not inside it.

**Still required despite D1.** `(meshtastic.field_metadata)` annotates *fields*, not
*enum values*. Picker option text — "Long Range - Fast", "Router", "United States" — comes
from `description` and `name` properties on the enums in `Meshtastic/Enums/`, and no
attribute in `FieldMetadata` reaches them. Covering those from the schema would need a
parallel `EnumValueOptions` extension, which #952 does not have and which is not proposed
here. So the option values that FR-004 requires be searchable are localized the ordinary
way, below.

**Rationale**: CLAUDE.md requires one change per pull request. The migration is a
mechanical sweep across 18 files that is independently valuable — those strings are
untranslated today regardless of search — and mixing it into the search PR would bury
the part needing review.

**Measured scope** (larger than the spec's "~200"):

- **321** `.localized` call sites in `Meshtastic/Enums/`, across 18 files and 39 enum
  properties. 319 have a string-literal receiver; 2 do not
  (`AppSettingsEnums.swift:174` and `:309`, both `self.rawValue.localized`).
- **259** distinct string values, of which **239 are absent** from
  `Localizable.xcstrings` (92%). The densest block is `RegionCodes.description` —
  37 country names at `LoraConfigEnums.swift:173-245`, none of them in the catalog.
- The 20 already present got there from unrelated `Text(...)` sites, not the enums.

**Mechanical form**: `"X".localized` → `String(localized: "X", comment: …)`. The return
type stays `String`, so all ~40 downstream consumers — `Text(...)`, `?? "Unknown"`,
string interpolation at `Firmware.swift:415`, `.accessibilityValue(...)` at
`MQTTConfig.swift:125` — are untouched. `LocalizedStringResource` was rejected for
exactly that reason: it would force conversions at every one of those sites for no gain.

**`UpdateIntervalPicker`**: change `pickerLabel: String` to `LocalizedStringKey`
(`UpdateIntervalPicker.swift:11` and the init at `:21`). All 19 call sites pass string
literals and type-check unchanged, and `Picker(pickerLabel, …)` then binds the localizing
overload. This is the precedent already set, with its explanatory comment, at
`Firmware.swift:624-628`.

**Keys to split rather than reuse**, because one translation cannot serve both senses:

| Key | Colliding senses |
|---|---|
| `Cancel` | the CANCEL key on an attached keypad vs. the dismiss-dialog verb |
| `All` | rebroadcast-everything vs. log-level filter vs. VoiceOver "no hop limit" |
| `Default` | serial baud rate vs. OSLog level vs. app icon vs. no channel selected |
| `Standard` | map type vs. the existing entry's offline-map-download comment |

**Adjacent bugs found, to fix in the same sweep**: `ScreenUnits.description`
(`DisplayEnums.swift:17-24`) returns bare `"Metric"`/`"Imperial"` with no `.localized` at
all; `DisplayEnums.swift:88` returns `"off".localized.capitalized`, where the catalog key
is `"Off"` and `.capitalized` is wrong for several locales.

**Process constraint**: there is no headless path to extract these keys. `Localizable.xcstrings`
is populated only as a side effect of an Xcode build, then machine-filled per locale by
`scripts/translate-locale.sh` and reviewed by a human. No CI workflow reads or validates
the catalog. Because the file is 3.1 MB and 1842 keys, the extraction commit must be
checked for an additive-only diff before pushing — `f3c6aab0` and `4cecf06a` in the
history are both cleanups after a rebuild went wide.

## D7. The annotated `label` is the search label; on-screen wording is untouched

**Decision**: `label` in the proto is the name search matches and displays in a result
row. It is *not* pushed back into the forms — no existing control is relabelled — and the
annotation should be written to match what the control already says, not the field name.

**Rationale**: proto field names and UI wording diverge freely, and the UI wording is
usually the better one. `hop_limit`'s control reads "Number of hops"
(`LoRaConfig.swift:522`); `sx126x_rx_boosted_gain` appears as `rxBoostedGain` with a
different label again. So the annotation carries the human phrasing — "Hop Limit" or
"Number of hops" as the screen has it — and `keywords` carries the rest ("hops", "ttl").
The spec's worked example, searching "hops", is served by the keyword either way.

Rewriting the forms to read their labels from the registry is a much larger change and is
out of scope here. It is the natural follow-on once every field is annotated, and it would
retire the D4 drift test by construction — worth noting, not worth doing now.

The field-to-control join stays a hand-written table for the reasons in D4. Only the
*screen*-level join is machine-derivable: `ConfigHeader(title:config:)` pairs a screen
title with a `KeyPath<NodeInfoEntity, T?>` at `ConfigHeader.swift:4-10`, used uniformly as
`config: \.loRaConfig`, `\.positionConfig`, `\.mqttConfig`. That ties a message to a
`SettingsNavigationState` destination.

## D8. Matching and ranking

**Decision**: `localizedStandardContains` for matching — case- and diacritic-insensitive,
and already documented as the house choice at `MessageSearch.swift:10`. Not
`lowercased().contains`, which `UserList.swift:465` uses and which is not diacritic-safe.

Ranking is field-weighted per FR-011: exact label, then label prefix, then keyword, then
description or option value. Ties break by section order then label, so results are
deterministic — `DocModels.swift:305-335` is the scoring precedent but sorts unstably,
which is the part not to copy.

## D9. Presentation

**Decision**: `.searchable(text:placement:.navigationBarDrawer(displayMode: .always), prompt:)`
on the existing Settings list, with the list body rendering filtered sections in place of
the full list while the query is non-empty.

`DocBrowserView.swift:69-94` is the working precedent — it filters a static catalogue,
drops empty sections with `compactMap`, and force-expands sections while searching
(`:56-67`). There is no shared search helper in the repo and one should not be invented
for this.

Navigation reuses `Router.settingsPath` (`Router.swift:31`), already deep-link capable
(`:281-287`), so a result can always push even when the corresponding list row is hidden —
which is what makes the agreed "show dimmed, with a note" behaviour implementable.

## Open items carried into implementation

- The in-app docs half of the index needs no research: `Meshtastic/Resources/docs/index.json`
  already carries `{id, title, section, navOrder, keywords}` for 31 pages and is generated
  by `scripts/build-docs.sh:163-178`, so it cannot drift.
- `SettingsNavigationState` is not `CaseIterable`; adding the conformance is the cheapest
  way to let the drift test enumerate destinations.
