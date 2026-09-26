# Data Model: Settings Search

**Feature**: 019-settings-search | **Date**: 2026-09-13 | **Verified against the code**: 2026-09-20

Nothing here persists. The index is static, built once from the generated registry plus the
generated app-level catalog and the bundled documentation index, and held in memory. Whether a
result is shown, dimmed or hidden is decided per query from connection and node state.

Type names below are the iOS reference implementation's, under `Meshtastic/Model/Search/`. The
shapes are the portable part; the names are not.

## Field identity (the join key)

Every schema-backed entry names the field it describes by **proto message full name and field
tag** — the same key the generated registry uses, `"meshtastic.Config.LoRaConfig#8"`. Nested
messages carry their full path (`meshtastic.ModuleConfig.MapReportSettings`), not a path through
the parent field.

Tag, not property name: property names diverge across the four representations of a field (proto
`sx126x_rx_boosted_gain`, generated `sx126XRxBoostedGain`, persisted `sx126xRxBoostedGain`, view
state `rxBoostedGain`), and the tag is the only one that is stable by contract.

App-level settings have no field identity.

The same identity is what a search result hands to the screen it opens, so the screen knows which
row to scroll to.

## Search entry

One row of the index. One control, one entry.

| Property | Type | Notes |
|---|---|---|
| `id` | `String` | Destination + label. Used for de-duplication and tests |
| `destination` | navigation case | Where tapping the result goes |
| `screenTitle` | `String` | Localized; the screen's own title, e.g. "LoRa" |
| `sectionTitle` | `String?` | Localized; the section within that screen. Always nil for schema-backed entries — the schema carries no section (spec FR-017) |
| `listSection` | enum | Which group of the Settings list the row sits in |
| `label` | `String` | Localized; what the control says on screen |
| `subtitle` | `String?` | Localized; the control's explanatory text |
| `keywords` | `[String]` | Localized synonyms; usually empty |
| `field` | identity? | nil for app-level settings |
| `requiresConnection` | `Bool` | Radio config is unavailable when disconnected |
| `requiresDeveloperBuild` | `Bool` | The Developers section renders only on debug and TestFlight builds, so its screens must not surface in search elsewhere |

Labels are not unique across the app — "Enabled" occurs six times — so identity is destination plus
label, never label alone, and results always render the screen alongside the label. This is also
why the string catalog keys on the field's full proto name rather than on the English: one
translation of "Enabled" cannot serve six controls in a language that inflects.

The index currently holds **233 entries**: 167 generated from the registry and 66 from the
generated app-level catalog. The catalog declares 68; two are dropped because the registry already
describes a control with the same label on the same screen (TAK Server shows `TAKConfig.team` and
`.role` alongside app-only controls). The schema wins those collisions, since its label is the one
every client shares.

Only `label` is reliably present. Of the 167 schema-backed entries, 144 carry a description and 6
carry keywords. Ranking weights label above keyword above description, so a sparse set costs
nothing, and per SC-002 findability is measured by a query corpus rather than by requiring every
entry to be padded out.

## Field metadata (the generated registry)

Read-only input, generated from `(meshtastic.field_metadata)` and `(meshtastic.enum_value_metadata)`
options. Field entries and enum-value entries share one table and one key format; an enum value is
keyed by the enum's full name and the value number.

```
diyOnly          Bool?
adminOnly        Bool?
minValue         Double?
maxValue         Double?
unit             String?
deprecated       Bool?      // mirrors the standard [deprecated = true] option
label            String?
description      String?
keywords         String?    // "|"-delimited
sinceFirmware    String?    // first firmware release that reads the field
deprecatedSince  String?    // first firmware release that stops reading it
```

The last two arrived after this feature shipped and are machine-readable version literals, not
display text. Everything else that is a string is display text and is localized.

Current contents of the registry as generated on `main`: **402 rows — 210 field entries and 192
enum-value entries.** The extra rows beyond the 187 field and 186 enum-value annotations in the
protos are entries generated from the standard `[deprecated = true]` option alone, which carry
nothing but `deprecated`.

Attribute coverage across the 167 schema-backed index entries: 144 descriptions, 27 units, 7
min/max pairs, 6 keyword strings, 3 `diyOnly`, 0 `adminOnly`. Across the whole registry, 16 rows
carry `sinceFirmware` and 5 carry `deprecatedSince`.

A field with no annotation resolves to nothing, which is treated as "visible, not deprecated, no
bounds". Absence is never a signal.

## Settings list section

The groups the Settings screen already uses, so a result's breadcrumb names the group the user
would otherwise have scrolled to: general, radio configuration, device configuration, configure,
logging, developers. Declaration order is also the tiebreak order for equally-scored results.

## Search result

An entry plus what the match was worth. Not stored; produced per keystroke.

| Property | Type | Notes |
|---|---|---|
| `entry` | search entry | |
| `score` | `Int` | Field-weighted per FR-011 |
| `visibility` | enum | `.normal`, `.deEmphasised(reason)`, or `.hidden` |

There is no separate availability flag; the reason a result is dimmed travels with the visibility
case, so nothing is de-emphasized without a reason the row can state.

Visibility is computed per query from an availability value — connected, DIY hardware, managed
radio, developer build — never baked into the index. The rules, in the order they are applied:

1. A developer-only screen on a build that does not render the Developers section is `.hidden`.
   There is nothing the user could do to reach it.
2. A `deprecated` field is `.deEmphasised`, marked as deprecated. Note this does **not** consult
   `deprecatedSince`; see spec FR-012c.
3. A `diyOnly` field on connected hardware not tagged DIY is `.hidden`. Disconnected, or with an
   unreadable hardware catalog, it is shown.
4. An `adminOnly` field is `.deEmphasised` as an advanced setting.
5. An entry needing a radio, with none connected or with a managed radio, is `.deEmphasised` with
   the respective reason.

Weights, highest first: exact label 1000, label prefix 500, label substring 250, keyword 100,
description 50. The label term and the other two add. Ties break by list section, then label, then
destination, so the order is fully determined — the index is built from a dictionary and would
otherwise reshuffle between launches, which is why the entries are sorted when the index is built.

## Documentation entries

The documentation half needs no new type. The bundled index carries `{id, title, section, navOrder,
keywords}` for 32 pages and is generated from the pages themselves, so it cannot drift from them.
Doc results render in their own section below the settings results and are never dimmed, since
documentation reads the same with or without a radio. A translated index replaces the bundled one
when it has been fetched.

## Option values

Picker option text comes from `enum_value_metadata` through the same registry, already localized,
and a value may carry its own description which the form shows under the picker when that value is
selected. A deprecated enum value is filtered out of a picker unless it is the value currently
held, so a node sitting on a retired preset can still see and change it.

Option values are **not** in the search index. An entry matches on its label, keywords and
description only, so "Long Range - Fast" does not find the Presets control. See spec FR-004.

## The settings forms

The registry is also what the configuration screens render from, which is not a search concern but
is the reason the annotations have to be good enough to read on screen:

- `label` is the control's title; a field with no label cannot be laid out at all.
- `description` is the explanatory line under it.
- `unit` is appended to a stepper's value, and `"s"` alone is enough to pick an interval control.
- `minValue`/`maxValue` give a slider or stepper its range; without both, the control falls back to
  a default range.
- `sinceFirmware`/`deprecatedSince` decide whether the control is offered for the target node's
  firmware at all.

What the schema does not supply, and each client decides alone: which fields share a section, in
what order, which controls depend on another field's value, and which fields are deliberately not
rendered. In this app those live in a per-screen Swift overlay next to the form
(`Meshtastic/Views/Settings/Config/Forms/`), holding no display text of its own.
