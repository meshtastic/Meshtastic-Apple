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
- A second protobufs change carrying the annotations is back on the critical path — see D5.

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

## D3. Three generator bugs fixed, and a guard added

Adding attributes in D1 meant exercising paths #952 had never run. All three were latent,
because every annotation the PR shipped with sets exactly one attribute and has no digit in
its name — the only case that worked. Fixed in `20fadc6` and `d6117b6` on
`jamesarich/field-metadata`, with tests that fail without the fix.

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

**The Go plugin's Swift naming was wrong.** Caught by the parity job the moment the field
annotations landed. `protoc-gen-fieldmeta` used a naive `snake_case` → `camelCase`, but
swift-protobuf's `NamingUtils.toLowerCamelCase` splits on *character-class* changes, so a
digit run starts a new segment and the letter after it is capitalised. Three fields in this
schema differ:

| proto | naive | swift-protobuf (correct) |
|---|---|---|
| `use_12h_clock` | `use12hClock` | `use12HClock` |
| `sx126x_rx_boosted_gain` | `sx126xRxBoostedGain` | `sx126XRxBoostedGain` |
| `use_i2s_as_buzzer` | `useI2sAsBuzzer` | `useI2SAsBuzzer` |

All three now match the committed `.pb.swift` exactly. This is the drift the Swift plugin's
README warns about, demonstrated: the pure-Swift sibling was right for free because it
calls swift-protobuf, while the Go port had to guess. `toLowerCamelCase` is now ported as
`swiftCamelCase` for the Swift target only — TypeScript keeps the naive rule it had — with
a test whose expected values are copied from real generated output rather than from the
implementation.

**A fourth change, not a bug: duplicate labels are now rejected.** Review on #1081 found five
`TrafficManagementConfig` fields annotated `label: "Enabled"` — the seeder had matched a
screen-level gate flag instead of the field's own control. The annotation was present and
syntactically valid, so nothing downstream could catch it, and a label is the source string
every client translates. Both generators now fail generation when two fields of one message,
or two values of one enum, share a label. Scoped per type, since "Enabled" once each on
`MQTTConfig` and `SerialConfig` is fine. A hard error rather than a CI check, matching the
scalar-only and generator-managed-`deprecated` guards.

Two smaller divergences fixed alongside: the Swift plugin mapped integer kinds to
`Int32`/`UInt32`/`UInt64` and float to `Float` where the Go plugin used `Int64` and
`Double`, so the two agreed only because bool, double and string are the only types in
use; and the Swift string escaper did not handle tabs, which the Go one did.

## D3a. Two things the generated registry cannot supply, found while wiring it

Both surfaced only on building the app against a real registry, and both are recorded here because
a reader of D2 would otherwise assume generation is the whole job.

**The generator emits no imports.** It cannot know which module holds the generated protobuf types —
that is the consumer's choice — and the file is full of `extension Config { … }`. `gen_protos.sh`
adds `import MeshtasticProtobufs` after generation.

**Its per-message static accessors break ordinary code across modules.** This one matters:

```swift
loraConfig.modemPreset = .shortFast
// error: static member 'modemPreset' cannot be used on instance of type 'Config.LoRaConfig'
```

A `public static var` added by an extension in module B shadows the *instance* property of a struct
from module A, for writes. Reads resolve correctly. In one file it compiles; across modules it does
not — and D2 forces our layout to be cross-module, since the registry must live in the app target
for its strings to be extracted.

The plugin's README claims the two coexist, citing `config.rxGpio` against
`Config.PositionConfig.rxGpio`. That holds for reading and was evidently not tested for assignment.

Reported upstream with a two-module repro, and fixed there: the Swift generators no longer emit
per-field message accessors at all (protobufs `c49d4ed`, on `master` via #952). Rather than nest
them under a namespace, they were dropped — the accessor was keyed on a name swift-protobuf
chooses rather than one the schema controls (`sx126x_rx_boosted_gain` generates as
`sx126XRxBoostedGain`), so only the tag is stable by contract. Kotlin keeps its field accessors,
because Wire keeps the proto's snake_case name.

The index uses `FieldMetadataRegistry.get(_:tag:)`, which is what it needed anyway. Enum accessors
are kept — `public var metadata` is an instance member on an enum and shadows nothing. The
interim `scripts/strip-fieldmeta-message-accessors.py` workaround has been deleted.

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
fields**. Of those, 155 are annotated and 37 are exempt under FR-015a; the rest have no
screen. Two messages sit outside the count on purpose:
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

**The exemption list is 37, not 16.** The smaller figure counted only fields the seeder examined.
Running the completeness test against a real registry surfaced 21 more — `buzzer_mode`,
`ipv6_enabled`, `use_long_node_name`, the health telemetry fields — which the seeder never saw
because the app has no save path for them. Each was checked for a control and has none: they are
firmware settings this client does not offer yet. That is a third exemption group, and the most
useful one, since a field leaving it is the signal that the app has caught up.

**One-to-many is mostly solved by annotating enum values, not fields.** A field carries
one `label`, so it cannot name ten toggles — but the ten toggles behind `position_flags`
are not really sub-fields. They are the values of the `PositionFlags` enum, which the
schema already declares; the field is a `uint32` bitfield over them. So the labels belong
on the *values*, and `(meshtastic.enum_value_metadata)` puts them there. Same mechanism
covers every picker's options.

Two genuine exceptions remain, both small and enumerated on the exemption list:

- `coding_rate` backs three controls (`LoRaConfig.swift:65-101`) — a preset/custom toggle
  and two sliders. That is app-side UI decomposition of one scalar, not a schema concept,
  and it stays curated.
- `tls_enabled` renders as two toggles (`MQTTConfig.swift:237-248`), but they are the same
  setting with different helper text depending on the server. One entry, not two — this
  was miscounted as a multi-label case earlier.

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

**Decision**: 019 depends on two upstream changes, deliberately kept apart so the mechanism
can be reviewed without the data on top of it. Both are open and fully green as of
2026-09-13.

| PR | Carries |
|---|---|
| [#952](https://github.com/meshtastic/protobufs/pull/952) | `field_metadata.proto` with both extensions, the Go and Swift generators, the byte-identical parity harness, localized string emission, the three fixes in D3. Five worked-example annotations, no bulk data. |
| [#1081](https://github.com/meshtastic/protobufs/pull/1081) | The annotations: 155 fields, 122 enum values. Based on #952's branch; retargets to `master` when #952 merges. |

The annotations went into #952 first and were split out afterwards — they are the data, not
the mechanism, and 262 lines of English on top of a generator change makes both harder to
review.

**The annotation work** has two halves.

*Enum values — done.* 122 values across 13 enums are annotated in
[#1081](https://github.com/meshtastic/protobufs/pull/1081), seeded
mechanically from the strings the app already carries: `RegionCode` 36, `Serial_Baud` 16,
`ModemPreset` 15, `Role` 12, `CompassOrientation` 8, `InputEventChar` 8,
`RebroadcastMode` 6, `Serial_Mode` 5, `DisplayMode` 4, `OledType` 4, `GpsMode` 3,
`PairingMode` 3, `DisplayUnits` 2. The join was by value number, which is aligned with
each app enum's raw value; names were not used for matching, since the app spells them
differently (`degrees0` vs `DEGREES_0`, `txtmsg` vs `TEXTMSG`).

*Fields — done.* 155 fields across 24 messages carry `label` and `description`, seeded from
the config views. Nothing in a view says which proto field a control edits, so the link came
from the save closure: `var lc = Config.LoRaConfig()` names the message,
`lc.hopLimit = UInt32(hopLimit)` ties the proto property to a `@State` var, and
`Picker("Number of hops", selection: $hopLimit)` supplies the label.

**37 fields are deliberately unannotated**, and they are the exemption list FR-015 needs:

- *Interpolated labels* — `Stepper(txPower == 0 ? "Max Transmit Power" : "\(txPower)dBm Transmit Power", …)`
  has no stable literal. Also `ls_secs`, `min_wake_secs`, the RGB values in
  `AmbientLightingConfig`, and the PaxCounter thresholds.
- *Controls in nested custom views* — `bandwidth` lives in `CustomBandwidthPicker`,
  `coding_rate` behind a preset toggle and two sliders.
- *No UI at all* — `private_key`, `admin_key`, `broadcast_targets`, `ipv4_config`.
- *`position_flags`*, unannotated by design: its ten toggles are enum values and carry
  their own labels.

`keywords` is not seeded for any field. It cannot be derived from the app, and inventing
synonyms mechanically would be guessing; labels and descriptions already carry the words a
user is most likely to type. Worth adding by hand where a term is genuinely absent — "psk"
for the pre-shared key control being the spec's own example.

**Eight values the app is behind on.** Annotating surfaced schema values with no app
string at all — `RegionCode.IN`, two `OLED_SH1107` variants, and six `Serial_Mode` values
(`DEFAULT`, `WS85`, `VE_DIRECT`, `MS_CONFIG`, `LOG`, `LOGTEXT`). They are newer than the
client. Once annotated upstream every client picks them up at once, which is the argument
for this design in miniature.

**What this costs**: unlike the previous plan, search cannot ship ahead of the
annotations — an index whose labels do not exist yet has nothing to match. The trade is
deliberate: one source of truth for what every setting is called, shared by Apple,
Android and web, instead of three hand-maintained copies.

## D6. Localization migration is its own change

**Decision**: FR-016 (the string-catalog migration) ships as a separate pull request,
before or alongside search, not inside it.

**Scope cut roughly in half by annotating enum values.** The earlier version of this
decision said picker option text could not come from the schema, because
`(meshtastic.field_metadata)` annotates fields and not enum values. That gap is now
closed: #952 carries a second extension, `(meshtastic.enum_value_metadata)`, so
"Long Range - Fast", "Router" and "United States" come from the schema like everything
else.

Of the 319 literal `.localized` sites in `Meshtastic/Enums/`, **127 sit on proto-backed
enums** and move to the schema — `RegionCodes` 37, `DeviceRoles` 24, `ModemPresets` 16,
`RebroadcastModes` 12, `CompassOrientations` 8, `InputEventChars` 8, `SerialModeTypes` 6,
`DisplayModes` 4, plus a handful of smaller ones.

The remaining **192 are app-only enums with no protobuf behind them** — `IntervalType`,
`RoutingError`, `ActivityType`, `FirmwareEditions`, `SupportLevel`, `KeyBackupStatus`, the
`AppSettings` enums — and those still need the migration below. So FR-016 shrinks but does
not go away, and the `UpdateIntervalPicker` fix is untouched by any of this.

**What replacing them looks like.** The app enums are not deleted: they carry ordering
(`DeviceRoles` lists `client, clientMute, clientHidden, tracker…`, deliberately not proto
order), `id`, icons and `protoEnumValue()`. Only the string properties go, from a switch
per value to a single lookup:

```swift
// before - one case per value, English only
var name: String {
    switch self {
    case .client: return "Client".localized
    ...
    }
}

// after - the schema is the source, already localized
var name: String {
    Config.DeviceConfig.Role(rawValue: rawValue)?.metadata?.label ?? ""
}
```

`isDeprecated` collapses the same way, onto the mirrored `deprecated` attribute, which
removes the hand-maintained list at `DeviceEnums.swift:23-31`. This cannot land until the
registry is generated into the app, so it belongs to the field-metadata wiring change in
the plan's sequencing, not to the search change.

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
