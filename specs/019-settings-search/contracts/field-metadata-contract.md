# Contract: protobuf field metadata

**Feature**: 019-settings-search | **Upstream**: meshtastic/protobufs#952

The boundary between this app and the protobufs repository. Everything the app is
entitled to assume, and everything it must not.

## What the app consumes

One generated file, `FieldMetadataRegistry.swift`, produced by
`tools/protoc-gen-fieldmeta-swift` from `(meshtastic.field_metadata)` options and
committed to `Meshtastic/Model/` — the app target, not the protobuf package.

The app reads exactly two things from it:

```swift
FieldMetadataRegistry.get("meshtastic.Config.LoRaConfig", tag: 8)   // -> FieldMetadata?
Config.LoRaConfig.hopLimit                                          // -> FieldMetadata
```

and from the returned value: `label`, `description`, `keywords`, `diyOnly`, `adminOnly`,
`deprecated`, `unit`, `minValue`, `maxValue`.

Enum values share the same registry and key format, keyed by the enum's full name and the
value number. Each enum type also gets an instance accessor:

```swift
Config.LoRaConfig.ModemPreset.longFast.metadata?.label   // -> "Long Range - Fast"
```

An instance property rather than a static, because a static named for the value would
collide with the enum case of that name.

## Guarantees relied on

1. **Keys are `"<full proto message name>#<tag>"`.** Nested messages use their full path,
   so `MapReportSettings` is `meshtastic.ModuleConfig.MapReportSettings`, not
   `meshtastic.ModuleConfig.MQTTConfig.map_report_settings`.
2. **Tags are stable.** A field's number never changes meaning. This is what lets the index
   key on tag rather than on any of the four diverging spellings of a field's name.
3. **`deprecated` mirrors the standard option.** The generators populate it from
   `[deprecated = true]`; setting it inside the annotation is a generation-time error. The
   app treats it as authoritative and shows those settings de-emphasised and marked rather
   than hiding them — see spec FR-012c.
4. **Labels are unique within a type.** Generation fails if two fields of one message, or two
   values of one enum, carry the same label, so the index can rely on `(destination, label)`
   distinguishing entries on the same screen. Across types they may repeat.
5. **Absence is not a signal.** A field with no annotation produces no registry entry.
   `get` returning `nil` means "nothing was said", never "not DIY-only" or "not deprecated".

## What the app must not assume

- **That the registry lists every field.** Entries exist only for fields carrying an
  annotation or the deprecated option. The authoritative list of settings is the `.proto`
  text; see research decision D4.
- **That the generated file can live anywhere.** String attributes are emitted as
  `String(localized:defaultValue:comment:)`, and Xcode extracts those only from a target
  that has a string catalog and `SWIFT_EMIT_LOC_STRINGS = YES`. Generated into
  `MeshtasticProtobufs`, the calls would still compile and would resolve to English
  forever, silently. This is the single most breakable part of the contract.
- **That a field's `label` names one control.** A field carries one label, but
  `position_flags` sits behind ten toggles. Those toggles are values of the `PositionFlags`
  enum, so their labels come from `(meshtastic.enum_value_metadata)` on the values, not from
  the field. `coding_rate`, which backs a preset toggle and two sliders with no enum behind
  them, stays curated.
- **That the attribute set can grow without touching the Swift plugin's binding.** Adding
  an attribute needs no generator *code* change — both plugins read values generically —
  but `protoc-gen-fieldmeta-swift` decodes the option through its own bundled
  `field_metadata.pb.swift`, so that binding must be regenerated or the new attribute
  arrives in `unknownFields`. Generation fails with a pointed error rather than dropping
  it.

## Localization

The English in the schema is the source string; translations live in
`Localizable.xcstrings`. The catalog key is the field's full proto name plus the attribute
(`meshtastic.Config.LoRaConfig.hop_limit.label`), never the English, so the six controls
labelled "Enabled" get six independently translatable entries.

Keys appear in the catalog only as a side effect of an Xcode build — there is no headless
extraction path in this repo. After regenerating the registry, build once and check the
`Localizable.xcstrings` diff is purely additive before committing.

## Degradation when #952 has not landed

The app must build with no registry at all. Until the submodule carries
`field_metadata.proto`, `FieldMetadataRegistry` is absent and lookup sites compile against
a local stub returning `nil`. Unlike the structural attributes, missing labels cannot be
defaulted — an entry with no label has nothing to match — so proto-backed entries simply
do not exist until the annotations land. App-level entries and documentation results work
throughout.

## Regeneration

`scripts/gen_protos.sh` gains a fourth phase after the existing `protoc` call at `:72`:

```bash
swift build --package-path protobufs/tools/protoc-gen-fieldmeta-swift -c release
protoc \
	--plugin=protoc-gen-fieldmeta-swift="$FIELDMETA_PLUGIN" \
	--proto_path=./protobufs \
	--fieldmeta-swift_out=./Meshtastic/Model \
	./protobufs/meshtastic/config.proto ./protobufs/meshtastic/module_config.proto
```

A separate invocation, not a second `--*_out` on the existing one, because the output
directory differs: the `.pb.swift` files go to the package, the registry to the app target
so its localized strings reach the catalog. The out path names the destination directory
directly, since this plugin emits a bare filename with no package-path prefix.

Unlike `protoc-gen-swift`, which `gen_protos.sh:57-64` builds from
`MeshtasticProtobufs/Package.resolved` so that plugin and runtime agree by construction,
this plugin is pinned by the `protobufs` submodule SHA.

## CI obligations

Two gaps must close for the completeness test to mean anything, both outside this app's
source:

- `unit-tests.yml:23` checks out without `submodules:`, so `protobufs/` is empty on every
  runner and a `.proto`-parsing test silently soft-skips. It needs `submodules: recursive`.
- `xcodegen-drift.yml`'s `paths:` filter does not include `protobufs` or `.gitmodules`, so
  a pull request that bumps only the submodule triggers no workflow at all.
