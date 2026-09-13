# Contract: protobuf field metadata

**Feature**: 019-settings-search | **Upstream**: meshtastic/protobufs#952

The boundary between this app and the protobufs repository. Everything the app is
entitled to assume, and everything it must not.

## What the app consumes

One generated file, `FieldMetadataRegistry.swift`, produced by
`tools/protoc-gen-fieldmeta-swift` from `(meshtastic.field_metadata)` options and
committed to `MeshtasticProtobufs/Sources/meshtastic/`.

The app reads exactly two things from it:

```swift
FieldMetadataRegistry.get("meshtastic.Config.LoRaConfig", tag: 8)   // -> FieldMetadata?
Config.LoRaConfig.hopLimit                                          // -> FieldMetadata
```

and from the returned value, only `diyOnly`, `adminOnly`, `deprecated`, `unit`,
`minValue`, `maxValue`.

## Guarantees relied on

1. **Keys are `"<full proto message name>#<tag>"`.** Nested messages use their full path,
   so `MapReportSettings` is `meshtastic.ModuleConfig.MapReportSettings`, not
   `meshtastic.ModuleConfig.MQTTConfig.map_report_settings`.
2. **Tags are stable.** A field's number never changes meaning. This is what lets the index
   key on tag rather than on any of the four diverging spellings of a field's name.
3. **`deprecated` mirrors the standard option.** The generators populate it from
   `[deprecated = true]`; setting it inside the annotation is a generation-time error. The
   app treats it as authoritative and hides those settings from results.
4. **Absence is not a signal.** A field with no annotation produces no registry entry.
   `get` returning `nil` means "nothing was said", never "not DIY-only" or "not deprecated".

## What the app must not assume

- **That the registry lists every field.** Entries exist only for fields carrying an
  annotation or the deprecated option. The authoritative list of settings is the `.proto`
  text; see research decision D4.
- **That string attributes are localizable.** `unit` and any future string attribute are
  emitted as plain Swift literals via `swiftStringLiteral(_:)`. They are invisible to
  Xcode's string-catalog extractor and are English by construction. `unit` is used only for
  short symbols such as "m", "s" and "dBm", which do not need translating; nothing
  user-facing in a sentence may come from here.
- **That the attribute set can grow freely.** `field_metadata.proto` states that adding an
  attribute is a schema-only change. That holds for the Go generator, which is generic, and
  not for the Swift one, whose `literal(for:shape:)` switches on attribute name and ends in
  `default: fatalError`. Adding a seventh attribute crashes the Swift plugin for every
  field until a case is added. Reported upstream; this feature adds no attributes.

## Degradation when #952 has not landed

The app must build and search correctly with no registry at all. Until the submodule
carries `field_metadata.proto`, `FieldMetadataRegistry` is absent and every lookup site
compiles against a local stub returning `nil`, which the index reads as "visible, not
deprecated, no bounds". Search then offers every indexed setting, including the nine
deprecated fields, and gains the filtering when the annotations arrive — no redesign, no
throwaway index entries.

## Regeneration

`scripts/gen_protos.sh` gains a fourth phase after the existing `protoc` call at `:72`:

```bash
swift build --package-path protobufs/tools/protoc-gen-fieldmeta-swift -c release
protoc \
	--plugin=protoc-gen-fieldmeta-swift="$FIELDMETA_PLUGIN" \
	--proto_path=./protobufs \
	--fieldmeta-swift_out=./MeshtasticProtobufs/Sources/meshtastic \
	./protobufs/meshtastic/config.proto ./protobufs/meshtastic/module_config.proto
```

A separate invocation, not a second `--*_out` on the existing one, because the output
directory differs. The out path names the `meshtastic` subdirectory directly: this plugin
emits a bare filename with no package-path prefix, and a loose file under `Sources/` would
break the package's implicit target path.

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
