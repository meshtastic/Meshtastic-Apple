# Data Model: Settings Search

**Feature**: 019-settings-search | **Date**: 2026-09-13

No SwiftData schema changes. The index is static, built at launch from compiled-in
declarations plus the bundled docs index, and held in memory. Nothing here persists.

## Field identity (the join key)

Every proto-backed entry names the field it describes by proto message name and tag —
the same key the generated registry uses, `"meshtastic.Config.LoRaConfig#8"`. Nested
messages carry their full path (`meshtastic.ModuleConfig.MapReportSettings`), which is
what `mqtt.mapReportSettings.positionPrecision` writes through.

Tag, not Swift property name: property names diverge across the four representations of
a field (proto `sx126x_rx_boosted_gain`, generated `sx126XRxBoostedGain`, entity
`sx126xRxBoostedGain`, view state `rxBoostedGain`), and the tag is the only one that is
stable by contract.

App-level settings have no field identity and carry `nil`.

## SettingsSearchEntry

One row of the index. One control, one entry — so a bitfield field such as
`position_flags` contributes ten entries that share a field identity, and a field with no
control contributes none.

| Property | Type | Notes |
|---|---|---|
| `id` | `String` | Stable; destination + label, used for diffing and tests |
| `destination` | `SettingsNavigationState` | Where tapping the result goes |
| `screenTitle` | `String` | Localized; the screen's own title, e.g. "LoRa" |
| `sectionTitle` | `String?` | Localized; the section within that screen |
| `listSection` | `SettingsListSection` | Which Settings group the row sits in |
| `label` | `String` | Localized; what the control says on screen |
| `subtitle` | `String?` | Localized; the control's explanatory text |
| `keywords` | `[String]` | Localized synonyms; usually empty, see below |
| `field` | `FieldIdentity?` | `nil` for app-level settings |
| `requiresConnection` | `Bool` | Radio config is unavailable when disconnected |

Labels are not unique across the app — "Enabled" occurs six times, "Options" twelve — so
identity is `destination` plus `label`, never `label` alone, and results always render the
screen and section alongside the label. This is also why the string catalog keys on the
field's full proto name rather than on the English: one translation of "Enabled" cannot
serve six controls in a language that inflects.

For proto-backed entries `label`, `subtitle` and `keywords` are read from the generated
registry, already localized. `keywords` arrives as a single `|`-delimited string, because
`FieldMetadata` attributes must be scalar; the entry splits and trims it. App-level entries
declare the same three fields by hand with `String(localized:)`.

Only `label` is reliably present. Of the 318 registry entries, 280 carry a label, 70 a
description and 5 keywords — a setting whose label already says what it is does not need
synonyms invented for it, and per SC-002 findability is measured by a query corpus rather
than by requiring every entry to be padded out. Ranking already weights label above keyword
above description, so a sparse set costs nothing.

## FieldIdentity

| Property | Type | Notes |
|---|---|---|
| `messageName` | `String` | Full proto name, e.g. `meshtastic.Config.LoRaConfig` |
| `tag` | `Int` | Proto field number |

Resolves against the generated registry to pick up `diyOnly`, `adminOnly`, `deprecated`,
`unit`, `minValue` and `maxValue`. A field with no annotation resolves to `nil`, which is
treated as "visible, not deprecated, no bounds" so the index works whether or not the
upstream annotations have landed.

## SettingsListSection

The three groupings `Settings.swift` already uses, so a result's breadcrumb matches the
list the user would otherwise have scrolled: `radioConfiguration`, `deviceConfiguration`,
`configure`. Ordering is the declaration order, which is also the tiebreak order for
equally-scored results.

## SettingsSearchResult

An entry plus what the match was worth. Not stored; produced per keystroke.

| Property | Type | Notes |
|---|---|---|
| `entry` | `SettingsSearchEntry` | |
| `score` | `Int` | Field-weighted per FR-011 |
| `isAvailable` | `Bool` | False when the entry needs a radio and none is connected |
| `visibility` | `Visibility` | `.normal`, `.deEmphasised(reason)`, or `.hidden` |

`visibility` is computed per query from connection and node state, not baked into the index,
which stays static. It is `.hidden` for a `diy_only` entry on non-DIY hardware (FR-012a) and
for a deprecated entry the radio does not currently hold (FR-012c); `.deEmphasised` when a
radio is needed and none is connected, when the field is `admin_only`, or when a deprecated
value is in use. Three rules, one mechanism, and nothing disappears without a reason the row
can state.

Weights, highest first: exact label match, label prefix, keyword match, then subtitle or
option-value match. Ties break by `listSection` order, then by `label`, so the order is
fully determined — `DocModels.swift:305-335` is the scoring precedent but sorts unstably,
which is the part not carried over.

## Documentation entries

The docs half needs no new type. `Meshtastic/Resources/docs/index.json` already carries
`{id, title, section, navOrder, keywords}` for 31 pages and is generated by
`scripts/build-docs.sh:163-178`, so it cannot drift from the pages it describes. Doc
results render in their own "Help & Documentation" section below the settings results and
are never dimmed, since documentation reads the same with or without a radio.

## Option values

Picker options are indexed as additional match text on the entry that owns the picker,
not as entries of their own — searching "Long Range - Fast" surfaces the Presets control
on LoRa rather than a free-floating row.

For proto-backed enums their text comes from `(meshtastic.enum_value_metadata)` through the
same registry, already localized: `preset.metadata?.label`. That covers 127 of the 319
`.localized` sites in `Meshtastic/Enums/`, including all 37 region names. The remaining 192
belong to app-only enums with no protobuf behind them and are localized by FR-016.

The ten toggles behind `position_flags` are indexed as ten entries sharing one field
identity, each taking its label from the corresponding `PositionFlags` value.

## Generated registry (external, from meshtastic/protobufs#952)

Read-only input, generated into `Meshtastic/Model/FieldMetadataRegistry.swift` — the app
target, not the protobuf package, so its localized strings reach the catalog:

```swift
public struct FieldMetadata {
    public var diyOnly: Bool?
    public var adminOnly: Bool?
    public var minValue: Double?
    public var maxValue: Double?
    public var unit: String?
    public var deprecated: Bool?
    public var label: String?
    public var description: String?
    public var keywords: String?
}

// Enum values share the registry; each enum type gets an instance accessor.
extension Config.LoRaConfig.ModemPreset {
    public var metadata: FieldMetadata? { ... }
}

public enum FieldMetadataRegistry {
    public static func get(_ messageType: String, tag: Int) -> FieldMetadata?
}
```

String attributes are emitted already resolved for the current locale:

```swift
"meshtastic.Config.LoRaConfig#8": FieldMetadata(
    minValue: 0.0, maxValue: 7.0,
    label: String(localized: "meshtastic.Config.LoRaConfig.hop_limit.label",
                  defaultValue: "Hop Limit",
                  comment: "label of meshtastic.Config.LoRaConfig.hop_limit"),
    ...)
```

Note `description` is a legal stored property here — the struct does not conform to
`CustomStringConvertible`, and the generated output is verified to typecheck.

Entries exist only for fields carrying `(meshtastic.field_metadata)` or the standard
`[deprecated = true]` option, so the registry is a source of *attributes*, never the list
of what settings exist. That list comes from the `.proto` text, per research decision D4.
