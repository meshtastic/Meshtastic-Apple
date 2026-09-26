# Quickstart: Settings Search

**Feature**: 019-settings-search | **Date**: 2026-09-13 | **Verified**: 2026-09-20

How to exercise the feature by hand, and what each check proves.

## US1 — find a setting without knowing its screen

Open Settings. The search field sits above the list and is always visible.

| Type | Expect |
|---|---|
| `hops` | "Hop Limit" on LoRa, under Radio Configuration |
| `psk` | Channels, matched on a keyword the screen never shows |
| `duty cycle` | "Override Duty Cycle" on LoRa |
| `transmit power` | "Transmit Power" on LoRa |
| `enabled` | several rows, each showing its own screen |

The last one is the point of the breadcrumb: "Enabled" is the label of six different controls, so a
result row is only useful with its screen beside it.

`Long Range - Fast` finds nothing. Picker option values are not indexed — see spec FR-004.

Tapping a result opens the screen and scrolls to the control it named. On a screen that is not
driven by the schema it simply opens. Where the control is laid out but hidden for the current
values — MQTT drops the credentials on the public server — the screen lands on the first visible row
of that control's section instead of doing nothing.

## US2 — search reaches the documentation

Type `mqtt`. Settings results come first, then a "Help & Documentation" section listing matching doc
pages. Tapping one opens the documentation browser.

Doc results are never dimmed — documentation reads the same whether or not a radio is connected.

## US3 — discover a feature while disconnected

Disconnect the radio, then search `hops` again.

The same results appear, dimmed, with a note that a radio connection is needed. Tapping still opens
LoRa, which shows its read-only state.

This is a deliberate divergence from the Settings list, which *hides* the configuration tree when
there is no node. Search dims rather than hides, because a user searching for something they cannot
currently reach is better served by being told why than by an empty result.

## Deprecated and firmware-gated settings

Search and the settings forms answer these differently today, which is worth seeing both ways.

Search `always point north`. The result appears, dimmed and marked "Deprecated", whatever firmware
the radio runs. Now open the Display screen on a radio running 2.7.1 or newer: the control is not
there, because the schema says firmware stopped reading `compass_north_top` at 2.7.1. On an older
radio it is present and works.

A deprecated field with no label at all — `gps_format`, `json_enabled` — has nothing to render and
nothing to match, so it appears in neither place.

That difference is a gap in search, not a decision — see spec FR-012c.

## Localization

Switch the device to a non-English locale and repeat US1. Result labels and descriptions should
render translated, since they come from the registry's localized strings.

Picker option values inside the forms are translated where the app reads them from the registry, and
still English-sourced where the app's own enums serve them — 123 `.localized` sites remain in
`Meshtastic/Enums/`, mostly region names, device roles and modem presets. That is the deferred half
of FR-016.

The catalog only gains keys as a side effect of an Xcode build; there is no headless extraction path.
After that build, check the catalog diff is purely additive before committing.

## Tests

- **Completeness** — parses `protobufs/meshtastic/{config,module_config}.proto` and asserts every
  field of a message that maps to a settings screen (203 of them across 24 messages) is indexed,
  exempt with a stated reason, or deprecated with no label. Needs the submodule checked out, which the
  unit-test workflow now does; without it the test soft-skips locally and records an issue on CI.
- **Per-screen counts** — pinned entry counts for LoRa, Bluetooth and Security, so a control added or
  annotated without thought fails rather than going quietly unsearchable.
- **Structural** — every destination is a real navigation case, no entry is blank, no two entries on a
  screen share a label, and no registry-backed label leaked its catalog key instead of resolving.
- **Catalog drift** — a CI workflow regenerates the app-level catalog from the views and fails if the
  committed file differs. It is not a unit test because the tests run in the simulator and cannot
  spawn the generator.
- **Ranking** — exact label beats prefix beats substring beats keyword beats description, and equal
  scores order by section then label, so the same query always returns the same order.
- **Matching** — case- and diacritic-insensitive, so `resume` matches `résumé`.
- **Query corpus** — "hops", "psk", "transmit power" and "region" each return their intended control
  in the top five. Grow it whenever a search that should have worked did not.
- **Form overlays** — separately, every configuration message is either laid out by an overlay or
  listed as deliberately hand-written, every field of a laid-out message is either rendered or omitted
  with a reason, and any field rendered without a registry label fails.
