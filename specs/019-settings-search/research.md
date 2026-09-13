# Research: Settings Search

**Feature**: 019-settings-search | **Date**: 2026-09-13

Phase 0 findings. Each decision below resolves an unknown left open by the spec or
the clarification session.

## D1. Split the index: proto registry for structure, string catalog for language

**Decision**: The generated field-metadata registry supplies the *spine* of the index —
which settings exist, their proto identity, bounds, unit, and whether they are
DIY-only, admin-only or deprecated. Labels, descriptions and search keywords stay in
app-side Swift, declared with `String(localized:)`, joined to the spine by the field's
proto identity (`"meshtastic.Config.LoRaConfig#3"`).

**Rationale**: The spec assumed user-facing strings could ride along in
`(meshtastic.field_metadata)` and be picked up by Xcode's string-catalog extractor.
They cannot. The Swift generator renders string attributes as plain Swift literals —
`protoc-gen-fieldmeta-swift/Sources/.../Generator.swift` builds them through
`swiftStringLiteral(_:)`, producing `unit: "m"`, not `String(localized: "m")`. A bare
`String` literal is invisible to the extractor, so any label shipped that way would be
permanently English.

The deeper reason is that a wire schema is the wrong home for UI copy. `config.proto`
is shared by Apple, Android, web, Python and firmware; translations are per-client
assets. Putting English labels in the proto would make them untranslatable in every
client at once, and would mean a translation fix required a protobuf release.

**Alternatives considered**:

- *Add `label` / `description` / `keywords` string attributes to `FieldMetadata` and
  teach the Swift generator to emit `String(localized:)`.* Rejected. It breaks the
  byte-identical Go/Swift parity that #952's `generator-parity` CI job enforces, and it
  bakes English into the wire schema.
- *Emit keys from the proto, then declare those keys in a separate catalog-visible Swift
  file.* Rejected. Two sources of truth with nothing enforcing they agree — renaming a
  label silently falls back to the key with no build error.

**Consequence**: the clarification question about a delimiter for a scalar-only keyword
string dissolves. App-side keywords are an ordinary Swift `[String]`; no packing needed.

## D2. The registry stays in `MeshtasticProtobufs`

**Decision**: Generate `FieldMetadataRegistry.swift` into
`MeshtasticProtobufs/Sources/meshtastic/`, next to the other generated protobuf code.

**Rationale**: D1 removes every user-facing string from the generated file, so the
constraint that forced it into the app target — being visible to `Localizable.xcstrings`
— no longer applies. Keeping it in the package puts generated code where generated code
already lives, and it inherits the existing SwiftLint exclusion (`.swiftlint.yml` and
`.swiftlint-precommit.yml` both exclude `MeshtasticProtobufs`, and nothing else relevant).
Had it gone into the app target it would have needed the `// swiftlint:disable all`
header that `config.pb.swift:3` carries, and it would have been the first generated
Swift in that target.

**Note**: the emitted `public struct FieldMetadata` has no explicit initializer, so its
memberwise init is internal to the package. Consumers read through the public
`FieldMetadataRegistry.get(_:tag:)` and the per-type static accessors; they never
construct a `FieldMetadata`. This is fine for our use and needs no upstream change.

**Two details that decide whether this works**:

- Point `--fieldmeta-swift_out` at `MeshtasticProtobufs/Sources/meshtastic`, not at
  `Sources`. Unlike `protoc-gen-swift`, this plugin emits a bare filename
  (`generatorOutputs.add(fileName: "FieldMetadataRegistry.swift")`) with no package-path
  prefix, so aiming at `Sources` would drop a loose file beside the one subdirectory.
  `MeshtasticProtobufs/Package.swift` declares no `path:` for its target and relies on
  SwiftPM's fallback of "exactly one directory under `Sources/`" — a loose file or a
  second directory there breaks the package build.
- The plugin is pinned differently from `protoc-gen-swift`. `gen_protos.sh:57-64` builds
  `protoc-gen-swift` out of `MeshtasticProtobufs/Package.resolved`, so plugin and runtime
  library versions agree by construction — a deliberate guard, documented at `:12-20`,
  against Homebrew's older plugin silently downgrading output. `protoc-gen-fieldmeta-swift`
  lives in the `protobufs` submodule, so it is pinned by the submodule SHA instead. That
  asymmetry is acceptable but must be stated, because the existing pin is load-bearing
  and a reader will assume it covers both.

## D3. The Swift generator is not schema-extensible — report upstream

**Finding**: `field_metadata.proto` documents that adding an attribute is "a SCHEMA-ONLY
change… No code generator or build change is needed". That holds for the Go plugin and
not for the Swift one.

- Go (`tools/protoc-gen-fieldmeta`) is generic: `fieldMetadataSchema` reads the attribute
  list off the extension descriptor, and `main.go:316` walks set values with
  `m.Get(xtd).Message().Range(...)`, rendering by `protoreflect.Kind`. A new scalar
  attribute flows through untouched.
- Swift (`protoc-gen-fieldmeta-swift`) emits the *struct* generically, but renders
  *values* in `literal(for:shape:)` via `switch f.name` over the six known attribute
  names, ending in `default: fatalError(...)`. That loop runs over every schema field for
  every entry, so adding a seventh attribute crashes the plugin immediately — for all
  fields, whether or not any of them sets it.

The `default:` comment claims "parity with the Go plugin's guard", but the Go plugin has
no such guard; it is generic by construction.

**Impact on this feature**: none directly — D1 means we add no attributes. Worth
reporting on #952 anyway, because the proto's own contract is the thing that is wrong.

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
- *Require `(meshtastic.field_metadata)` on all 221 fields so the registry is complete.*
  Rejected — it makes an unrelated upstream protobuf PR a hard blocker for this feature
  and annotates fields that have nothing worth annotating.

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

## D5. Upstream dependency is smaller than the spec assumed

**Decision**: 019 depends on meshtastic/protobufs#952 only for the `diy_only`,
`admin_only` and `deprecated` signals that decide whether a setting should be offered in
search results. It does **not** depend on a follow-on annotation PR covering all 221
fields, and it does not depend on any `FieldMetadata` schema change.

**Status of #952** (checked 2026-09-13): open, mergeable, all seven checks green
(`build`, `build-kmp`, `go-plugin-test`, `generator-parity`, `ascii-dash`, CodeRabbit,
CLA). It annotates 3 fields in `config.proto` as a demonstration.

**Consequence**: if #952 slips, 019 ships with every setting treated as visible and
non-deprecated, and gains the filtering later without a redesign. That removes the
critical-path dependency the spec carried.

## D6. Localization migration is its own change

**Decision**: FR-016 (the string-catalog migration) ships as a separate pull request,
before or alongside search, not inside it.

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

## D7. Search labels are indexed labels, not a rename of the screens

**Decision**: The index carries its own label for each entry, matched to what the control
actually says on screen. The registry does not become the source of truth for on-screen
labels, and no existing control is relabelled to match a proto field name.

**Rationale**: proto field names and UI labels diverge freely and the UI wording is
usually the better one. `hop_limit`'s control reads "Number of hops"
(`LoRaConfig.swift:522`); `sx126x_rx_boosted_gain` is `@State rxBoostedGain` with a
different label again. Treating the proto name as the label would regress wording that was
chosen deliberately, and the spec's own worked example — searching "hops" — depends on the
UI phrasing, not the field name.

The practical consequence is that the field-to-control join is a hand-written table, not a
derivation. Only the *screen*-level join is machine-derivable: `ConfigHeader(title:config:)`
pairs a screen title with a `KeyPath<NodeInfoEntity, T?>` at
`ConfigHeader.swift:4-10`, used uniformly as `config: \.loRaConfig`, `\.positionConfig`,
`\.mqttConfig`. That is what ties a message to a `SettingsNavigationState` destination; the
per-field rows below it are curated, and D4's completeness test is what keeps them honest.

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
