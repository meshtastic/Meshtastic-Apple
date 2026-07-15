# protoc-gen-fieldmeta-swift

A pure-Swift protoc plugin that generates `FieldMetadataRegistry.swift` from
`(meshtastic.field_metadata)` field options — the structured, app-facing field
metadata proposed in [meshtastic/protobufs#952](https://github.com/meshtastic/protobufs/pull/952)
(e.g. `diy_only` on `Config.PositionConfig.rx_gpio`, so apps can hide DIY-only
settings on pre-assembled boards).

This is the Swift-native equivalent of that PR's Go `protoc-gen-fieldmeta`,
verified to produce **byte-identical output** over the same schema. It exists so
this repo's protobuf pipeline stays entirely within the Swift toolchain — no Go
required on contributor machines or CI.

## Why a Swift implementation

- Built on `SwiftProtobufPluginLibrary` — the same library `protoc-gen-swift`
  itself uses. Emitted type paths (`Config.PositionConfig`) and property names
  (`rxGpio`) come from swift-protobuf's own `SwiftProtobufNamer`/`NamingUtils`,
  so they match the app's real generated code **by construction** instead of by
  reimplementing the snake_case→camelCase rules and hoping they agree (fields
  like `pm10_standard` are exactly where hand-rolled conversions drift).
- The `(meshtastic.field_metadata)` option is registered via the library's
  `customOptionExtensions` hook, so it arrives as a typed value on
  `field.options` — no descriptor byte-parsing.
- The emitted `FieldMetadata` struct's shape is driven by the schema: adding a
  new *scalar* attribute to `field_metadata.proto` flows through automatically.
  (Value emission for a new attribute needs a one-line `case` in
  `Generator.swift` — the plugin fails loudly, never silently drops metadata.)

## Status

**Inert until meshtastic/protobufs#952 merges** — the `field_metadata.proto`
option doesn't exist in the `protobufs/` submodule yet, so nothing invokes this
plugin. It is vendored ahead of time so the pipeline change is a one-liner when
upstream lands.

## Usage (once protobufs#952 is in the submodule)

Add to `scripts/gen_protos.sh`, alongside the existing `--swift_out`:

```bash
swift build -c release --package-path tools/protoc-gen-fieldmeta-swift
protoc --proto_path=./protobufs \
  --plugin=protoc-gen-fieldmetaswift=tools/protoc-gen-fieldmeta-swift/.build/release/protoc-gen-fieldmeta-swift \
  --fieldmetaswift_out=./MeshtasticProtobufs/Sources/meshtastic \
  ./protobufs/meshtastic/*.proto
```

The output (`FieldMetadataRegistry.swift`) lands next to the other generated
sources in `MeshtasticProtobufs` and is used like:

```swift
let hideOnRetail = Config.PositionConfig.rxGpio.diyOnly ?? false   // typed accessor
FieldMetadataRegistry.get("meshtastic.Config.PositionConfig", tag: 8) // dynamic lookup
```

## Regenerating `field_metadata.pb.swift`

`Sources/protoc-gen-fieldmeta-swift/meshtastic/field_metadata.pb.swift` is the
plugin's own generated binding for the option schema (currently generated from
protobufs PR #952 at `007d7b2`, with the `protoc-gen-swift` matching
`MeshtasticProtobufs`' resolved swift-protobuf version). Once the proto is in
the submodule, regenerate with:

```bash
protoc --proto_path=./protobufs \
  --swift_opt=Visibility=Public \
  --swift_out=tools/protoc-gen-fieldmeta-swift/Sources/protoc-gen-fieldmeta-swift \
  ./protobufs/meshtastic/field_metadata.proto
```

## Verification (2026-07-15, against protobufs PR #952 @ 007d7b2)

- Output diffed **byte-for-byte identical** to the Go `protoc-gen-fieldmeta`.
- Generated registry compiles clean inside the real `MeshtasticProtobufs`
  package (swift-protobuf 1.36.1), and an external consumer typechecks the
  typed accessor, the dynamic lookup, and static/instance member coexistence
  (`config.rxGpio` value vs `Config.PositionConfig.rxGpio` metadata).
