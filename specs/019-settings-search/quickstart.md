# Quickstart: Settings Search

**Feature**: 019-settings-search | **Date**: 2026-09-13

How to exercise the feature by hand once it is built, and what each check proves.

## US1 — find a setting without knowing its screen

Open Settings and pull down to reveal the search field.

| Type | Expect |
|---|---|
| `hops` | "Number of hops" on LoRa, under Radio Configuration |
| `psk` | the pre-shared key control on Channels |
| `duty cycle` | "Override Duty Cycle" on LoRa |
| `Long Range - Fast` | the Presets control on LoRa, matched on an option value |
| `enabled` | several rows, each showing its own screen and section |

The last one is the point of the breadcrumb: "Enabled" is the label of six different
controls, so a result row is only useful with its screen and section beside it.

Tapping any result opens that screen. It does not scroll to or highlight the control —
`position_flags` alone backs ten toggles, so there is no single control to anchor on.

## US2 — search reaches the documentation

Type `mqtt`. Settings results come first, then a "Help & Documentation" section listing
matching doc pages. Tapping one opens the page in the docs browser.

Doc results are never dimmed — documentation reads the same whether or not a radio is
connected.

## US3 — discover a feature while disconnected

Disconnect the radio, then search `hops` again.

The same results appear, dimmed, with a note that a radio connection is needed. Tapping
still opens LoRa, which shows its existing "Please connect to a radio" header
(`ConfigHeader.swift:33-35`).

This is a deliberate divergence from the Settings list, which *hides* the configuration
tree when there is no node (`Settings.swift:674`). Search dims rather than hides, because
a user searching for something they cannot currently reach is better served by being told
why than by an empty result.

## Localization

Switch the device to a non-English locale and repeat US1. Every result label, section and
option value should render translated. English text that appears is a string that has not
reached `Localizable.xcstrings`, and it comes from one of two places:

- **Labels, descriptions, keywords** — annotated in the protobufs and emitted by the
  generator as `String(localized:)`. Missing means either the field is not yet annotated,
  or the registry was generated into the wrong target: `SWIFT_EMIT_LOC_STRINGS` is
  per-target, so a registry in `MeshtasticProtobufs` compiles fine and silently stays
  English. Check `Meshtastic/Model/FieldMetadataRegistry.swift` exists.
- **Picker option values** — "Long Range - Fast", "Router", "United States" — which come
  from the enums, not the schema. That is FR-016, and the reason it ships as its own
  change.

The catalog only gains keys as a side effect of an Xcode build; there is no headless
extraction path. After that build, check the `Localizable.xcstrings` diff is purely
additive before committing — it is 3.1 MB and 1842 keys, and a rebuild that reorders or
prunes produces an unreviewable diff.

## Tests

- **Completeness** — parses `protobufs/meshtastic/{config,module_config}.proto` and asserts
  each of the 221 fields is either indexed or on the exemption list with a reason. Requires
  `submodules: recursive` on the `unit-tests.yml` checkout, or it soft-skips and proves
  nothing.
- **Drift** — asserts every entry's label still occurs as a string literal in the view file
  for its screen, and that every `destination` is a real `SettingsNavigationState` case.
  Renaming a label without updating its entry must fail this (SC-003).
- **Per-screen counts** — a pinned entry count per screen, so a control added to a form
  without a matching index entry fails rather than going quietly unsearchable.
- **Ranking** — exact label beats prefix beats keyword beats subtitle, and equal scores
  order by section then label, so the same query always returns the same order.
- **Matching** — `localizedStandardContains`, so `resume` matches `résumé` and case is
  ignored.
