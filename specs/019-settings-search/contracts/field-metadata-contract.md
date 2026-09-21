# Contract: protobuf field metadata

**Feature**: 019-settings-search | **Upstream**: `meshtastic/protobufs`
**Verified against the submodule pin on `main`**: 2026-09-20

The boundary between a client and the protobufs repository. Everything a client is entitled to
assume, and everything it must not. Written to be portable — the Swift specifics are marked.

## What the schema carries

`meshtastic/field_metadata.proto` defines one message, `FieldMetadata`, carried in two extensions
that share extension number **51001**:

- `(meshtastic.field_metadata)` on `google.protobuf.FieldOptions`
- `(meshtastic.enum_value_metadata)` on `google.protobuf.EnumValueOptions`

Extension numbers are scoped per extendee, so sharing the number is deliberate. Reusing the same
message for both means one shape, one registry and one localization path for fields and for the
enum values a picker offers.

Attributes, in field-number order:

| # | Attribute | Kind | What it is |
|---|---|---|---|
| 1 | `diy_only` | bool | Only relevant to DIY hardware builds |
| 2 | `admin_only` | bool | Advanced or administrative; may be de-emphasized |
| 3 | `min_value` | double | Inclusive lower bound, **presentation only** |
| 4 | `max_value` | double | Inclusive upper bound, **presentation only** |
| 5 | `unit` | string | Human-facing unit — `"m"`, `"s"`, `"dBm"` |
| 6 | `deprecated` | bool | Mirrors the standard `[deprecated = true]` option |
| 7 | `label` | string | What a UI labels the control that edits this |
| 8 | `description` | string | One-sentence plain-language explanation |
| 9 | `keywords` | string | `\|`-delimited search synonyms |
| 10 | `since_firmware` | string | First firmware release that reads the field, e.g. `"2.7.12"` |
| 11 | `deprecated_since` | string | First firmware release that stops honoring it |

Attributes are **scalar by rule**. A message, enum, bytes, repeated or map attribute is rejected at
generation time, and so is any 64-bit integer kind, because TypeScript's `number` cannot hold one
exactly. That is why a keyword list travels as one delimited string. Float attributes must be
finite; an open bound is left unset rather than set to infinity.

Adding an attribute is a schema-only change: every generated registry — Kotlin/Wire, C, Python,
TypeScript, Rust, Swift — picks it up without a generator code change. The one exception is the
Swift plugin, which decodes the option through its own generated binding for this file rather than
by reflection, so that binding must be regenerated or the new attribute lands in `unknownFields`.
It fails loudly rather than dropping it.

`deprecated` is the one attribute never set by hand. The generators populate it from the field's
standard `[deprecated = true]` option, because protobuf runtimes strip options and the standard
bit is otherwise invisible at runtime. Setting it inside an annotation is a generation-time error.

## Which strings are display text

`label`, `description`, `unit` and `keywords` are user-facing display text. The English in the
schema is the **source string**; translations belong in the consuming client, keyed by the field's
full proto name plus the attribute (`meshtastic.Config.LoRaConfig.hop_limit.label`), never by the
English. Six different controls are labeled "Enabled" and one translation cannot serve all six.

Do not put machine-readable values — regexes, identifiers, format codes — in a display-text
attribute; they would be handed to translators.

`since_firmware` and `deprecated_since` are the exception: they are compared, not read, and are
emitted as plain literals.

**(Swift only)** the Swift generator emits display strings as
`String(localized:defaultValue:comment:)`, so Xcode's extractor pulls them into the app's string
catalog on build. Extraction is per-target, so the registry must be generated into the app target,
not into the protobuf package — generated into the package it would compile and resolve to English
forever, silently. This is the single most breakable part of the Swift setup. Other toolchains will
have their own equivalent; the portable requirement is only that the key is the proto name.

## Registry shape

One generated table keyed `"<full proto message or enum name>#<tag or value number>"`:

```
FieldMetadataRegistry.get("meshtastic.Config.LoRaConfig", tag: 8)
FieldMetadataRegistry.get("meshtastic.Config.LoRaConfig.ModemPreset", tag: 0)
```

Nested messages use their full path, so `MapReportSettings` is
`meshtastic.ModuleConfig.MapReportSettings`, not a path through the parent field.

**(Swift only)** each annotated enum type also gets an instance accessor, so
`ModemPreset.longFast.metadata?.label` works. An instance property rather than a static, because a
static named for the value would collide with the enum case.

As generated on `main` the table holds 402 rows: 210 field entries and 192 enum-value entries.

## Guarantees relied on

1. **Keys are `"<full proto name>#<tag>"`.** Enum values key on the enum's full name and the value
   number.
2. **Tags are stable.** A field's number never changes meaning. This is what lets a client key on
   tag rather than on any of the diverging spellings of a field's name.
3. **`deprecated` mirrors the standard option**, and is authoritative.
4. **Labels are unique within a type.** Generation fails if two fields of one message, or two values
   of one enum, carry the same label, so a client can rely on (screen, label) distinguishing entries
   on the same screen. Across types they repeat freely.
5. **Absence is not a signal.** A field with no annotation produces no entry. A lookup returning
   nothing means "nothing was said", never "not DIY-only" or "not deprecated".

## What a client must not assume

- **That the registry lists every field.** Entries exist only for fields carrying an annotation or
  the deprecated option. The authoritative list of what settings exist is the `.proto` text.
- **That a bound is enforced.** `min_value` and `max_value` are presentation metadata, deliberately,
  and overlap protovalidate, which is the thing to reach for where a constraint must be *enforced*.
  These exist because the consumers that most need a bound cannot evaluate CEL against a descriptor
  at runtime — nanopb on the firmware, and the generated types clients use. A bound stated here and a
  bound enforced in firmware can drift and nothing detects it, so the firmware is the source of truth.
- **That a field's `label` names one control.** A field carries one label, but `position_flags` sits
  behind ten toggles. Those toggles are values of the `PositionFlags` enum, so their names come from
  `enum_value_metadata` on the values. Conversely `coding_rate` backs a preset toggle and two sliders
  with no enum behind it, and no annotation can express that.
- **That the schema says where a control goes.** There is no `section`, `order` or field-dependency
  attribute. See "What the schema does not carry" below.

## The firmware window

`since_firmware` and `deprecated_since` were added after search shipped, and they are the part most
likely to be implemented inconsistently between clients. The schema states the rule in the
`deprecated_since` comment:

> show the field below this version; at or above it, treat it as `deprecated` does

The reasoning, which is worth repeating because the naive reading is wrong: `deprecated` says only
that a field is superseded. The replacement's arrival and the old field's removal are usually
different releases — `compass_orientation` replaced `compass_north_top` in 2.3.13, but firmware went
on reading the old field until 2.7.1. A client that hides the old field on the strength of the
boolean alone takes a working setting away from every node between those releases. Both clients did
exactly that before these attributes existed.

Practical rules this app applies, offered as a starting point rather than as a standard:

- Compare against the **target node's** firmware version, not whatever radio is connected — under
  remote administration those are different radios on different firmware.
- A node whose firmware version is unknown shows everything. Offering a control the radio ignores is
  a smaller failure than hiding a setting somebody came to change.
- Do not substitute "the node holds a non-default value" for the version test. Firmware force-writes
  some deprecated fields — `canned_message.enabled` is set true from 2.7.4 — so that test shows those
  rows on every modern radio.
- `deprecated` is not "removed". A field firmware has stopped reading entirely is a different
  statement and wants its own annotation.
- The same attribute on `ModuleConfig`'s own fields says when a module arrived, which is enough to
  decide whether to offer its settings screen at all.

## What the schema does not carry

Nothing in `FieldMetadata` says:

- which fields belong in the same section, or what that section is called;
- what order fields appear in — proto tag order is declaration history, not a layout;
- that one control only matters while another field holds a particular value;
- that a field exists but should deliberately not be rendered.

Every client decides these independently and nothing keeps them in step. This app keeps them in a
per-screen overlay written in code rather than data, holding no display text, so that a field the
schema renames fails to compile instead of failing to render; its tests assert that every renderable
field of a message is either laid out or omitted with a stated reason. If a section or order
attribute is ever added upstream, those overlays should shrink.

## Localization

Keys reach the string catalog only as a side effect of an Xcode build — there is no headless
extraction path in this repo. **(iOS only)** after regenerating the registry, build once and check
the catalog diff is purely additive before committing.

## Regeneration

`scripts/gen_protos.sh` runs the field-metadata plugin over `protobufs/meshtastic/*.proto` as a
separate `protoc` invocation from the one that builds the message types, because the output
directories differ: the generated messages go to the Swift package, the registry to the app target.
The plugin emits no imports — it cannot know which module holds the generated protobuf types — so
the script adds the one import afterwards. It also refuses to overwrite a populated registry with an
empty one, which is what generating against un-annotated protos would silently produce.

The plugin is pinned by the `protobufs` submodule SHA, not by the Swift package resolution that
pins `protoc-gen-swift`.

A second, app-local plugin (`scripts/protoc-gen-configform-swift`) generates a typed field
descriptor per configuration field — tag, proto name, kind, and a key path into the generated
message — which is what lets the settings forms read a field without naming it by string. It carries
no display text; labels and units are looked up in the registry at runtime by message name and tag.

## CI obligations

Both gaps the original contract named are closed: the unit-test workflow checks out submodules
recursively, so the `.proto`-parsing completeness test has something to read, and the project-drift
workflow's path filter includes `protobufs` and `.gitmodules`, so a submodule-only bump still runs.
