# Feature Specification: Settings Search

**Feature Branch**: `019-settings-search`
**Created**: 2026-09-13
**Last verified against the code**: 2026-09-20
**Status**: Shipped — [#2487](https://github.com/meshtastic/Meshtastic-Apple/pull/2487). The schema half
has since grown two attributes and now drives the settings forms as well as search; see Progress below.
**Input**: User description: "a settings search view to help users find features similar to how settings
search works on iOS and Mac", extended to cover every individual setting, the in-app documentation, and
generation of the index from protobuf field metadata.

**Audience**: written for anyone building the same thing on another client, not only for this app. The
mechanism and the client rules are the portable part and are stated as such. Where something is specific
to the iOS app it is marked **(iOS only)**, and where a decision was made here that has no home in the
schema it is marked **(app-owned)** — those are the places two clients will silently diverge.

## Overview

Settings has 42 destinations. 23 of them are radio or module configuration screens backed by a
`Config` or `ModuleConfig` message; the rest are app-level screens — App Settings, Channels, Routes,
Tools, the documentation browser. A user who knows a feature exists frequently cannot find which
screen holds it: hop limit is on LoRa, pre-shared keys are on Channels, and nothing in the interface
says so. iOS and macOS answer this with a search field at the top of Settings.

The search covers three kinds of result: the settings screens themselves, the individual controls on
them, and the in-app documentation pages. Typing filters the Settings list in place rather than
pushing a separate results screen.

The index for radio and module settings is **generated from protobuf metadata**, not hand written, so
it cannot drift from the schema it describes. Labels, descriptions, units, bounds and firmware windows
come from `(meshtastic.field_metadata)` on the field; picker option text comes from
`(meshtastic.enum_value_metadata)` on the enum values. App-level settings have no protobuf behind
them and are generated from the views instead, with a CI check that fails when that file is stale.

The English in the schema is the **source string** for translation. **(iOS only)** the Swift generator
emits it as `String(localized:defaultValue:comment:)` keyed by the field's full proto name, so Xcode's
extractor pulls it into the app's string catalog and translations live in the app rather than in the
wire schema. The portable part of that decision is: the schema carries English, each client localizes
it under a key derived from the field's full proto name, never under the English text — six different
controls are labeled "Enabled", and one translation cannot serve all six.

**The registry is no longer only a search index.** 22 of the 23 configuration screens now render
themselves from the same annotations: the label beside the control, the explanatory line under it, the
unit on a stepper, the slider's range, which firmware versions the control is offered on, and the text
of every picker option. Search was the first consumer; the settings UI is the larger one. That changes
the bar the annotations have to clear — a label that is good enough to match a query is not
automatically good enough to be the control's name on screen, which is why some of the pending upstream
work is rewording rather than adding.

## Progress

**Upstream (meshtastic/protobufs)** — merged

| | |
|---|---|
| Schema and generators — [#952](https://github.com/meshtastic/protobufs/pull/952) | Merged 2026-09-15 |
| Annotations — [#1081](https://github.com/meshtastic/protobufs/pull/1081) | Merged 2026-09-17 |
| Descriptions and units from the iOS helper text — [#1101](https://github.com/meshtastic/protobufs/pull/1101) | Merged 2026-09-18 |
| `since_firmware` and `deprecated_since` — [#1104](https://github.com/meshtastic/protobufs/pull/1104) | Merged 2026-09-19 |
| Enum-value labels for the remaining pickers — [#1103](https://github.com/meshtastic/protobufs/pull/1103) | Merged 2026-09-19 |

As of the submodule pin on `main`, the schema carries **187 field annotations and 186 enum-value
annotations** across `config.proto`, `module_config.proto` and `atak.proto`. 16 entries carry
`since_firmware` and 5 carry `deprecated_since`.

**Upstream — open, and they will change what clients render**

| | |
|---|---|
| [#1106](https://github.com/meshtastic/protobufs/pull/1106) | Labels eight config fields that currently have none, so a schema-driven form can render them at all |
| [#1108](https://github.com/meshtastic/protobufs/pull/1108) | `deprecated_since` on eight older deprecations that #1104 did not reach |

[#1107](https://github.com/meshtastic/protobufs/pull/1107) — eighteen labels reworded from sentences
to control names — was **closed without merging on 2026-09-20**. Those labels still read as
descriptions ("Alert GPIO buzzer when receiving a message" is a row title today), and any client
rendering forms from the schema will show them that way until it is reopened or replaced.

**This repository**

| | |
|---|---|
| Settings search, the registry wiring and the string-catalog work — [#2487](https://github.com/meshtastic/Meshtastic-Apple/pull/2487) | Merged 2026-09-18 |
| Search results land on the control, not just the screen — [#2512](https://github.com/meshtastic/Meshtastic-Apple/pull/2512), [#2514](https://github.com/meshtastic/Meshtastic-Apple/pull/2514) | Merged; supersedes the original FR-013 |
| 22 configuration screens migrated to the metadata-driven form — [#2505](https://github.com/meshtastic/Meshtastic-Apple/pull/2505) through [#2530](https://github.com/meshtastic/Meshtastic-Apple/pull/2530) | Merged |
| Replacing the app's own proto-backed enum strings with registry lookups | Still deferred — 123 literal `.localized` sites remain in `Meshtastic/Enums/` |

#2489, #2490 and #2491 were closed; their content landed in #2487.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find a setting without knowing its screen (Priority: P1)

A user wants to change how many times their messages are repeated across the mesh. They know the
word "hops". They open Settings, type it, and get the control itself — not just a screen to go
hunting through.

**Why this priority**: This is the feature. Everything else is elaboration on it.

**Independent Test**: Type "hops" in Settings and confirm a result identifying the hop-limit control
and the screen it lives on; tapping it opens that screen at that control.

**Acceptance Scenarios**:

1. **Given** the Settings list, **When** the user types "hops", **Then** a result appears showing the
   LoRa `Hop Limit` control, grouped under a "Radio Configuration" heading with "LoRa" beneath the
   label.
2. **Given** a result is shown, **When** the user taps it, **Then** the app navigates to that settings
   screen and scrolls to the named control.
3. **Given** the user types "psk", **Then** Channels appears — the term never appears in that screen's
   title, so this only works if synonyms are indexed.
4. **Given** the user clears the query, **Then** the full Settings list returns unchanged.

---

### User Story 2 - Search reaches the documentation too (Priority: P2)

A user searching "hops" may want to change the setting or to understand what hops are. Both answers
live in the app, and the search field offers both.

**Why this priority**: The documentation is already indexed and bundled; surfacing it costs little and
answers the question behind the question.

**Independent Test**: Search a term that appears in both a setting and a documentation page, and
confirm both appear under distinct section headings.

**Acceptance Scenarios**:

1. **Given** a query matching both, **Then** settings results appear first, under their own section
   headings, followed by a "Help & Documentation" section.
2. **Given** a documentation result, **When** the user taps it, **Then** the documentation browser opens.
3. **Given** a query matching only documentation, **Then** only the documentation section is shown —
   empty sections never render.

---

### User Story 3 - Discover a feature while disconnected (Priority: P3)

A user without a radio connected searches for a feature to learn whether the app supports it at all.

**Why this priority**: Knowing a capability exists is most of the value of search, and the Settings
list currently hides the entire configuration tree when no radio is connected, so search is the only
way to discover it.

**Independent Test**: With no radio connected, search a radio-configuration term and confirm the
result is listed, visibly de-emphasized, with an explanation.

**Acceptance Scenarios**:

1. **Given** no connected radio, **When** the user searches a radio-configuration term, **Then** the
   result is shown dimmed with a note that it needs a connected radio.
2. **Given** such a result is tapped, **Then** the app still navigates to the screen, which presents
   its existing read-only state rather than an error.

---

### Edge Cases

- A control whose visible label is generic — "Enabled" appears on six different screens — is
  distinguishable only by its screen, so the screen forms part of its identity rather than decoration.
- A module excluded on the connected node, or requiring newer firmware, is absent from the Settings
  list but still present in the index — the index is static while the list is node-dependent.
- A managed radio shows no configuration sections; search behaves as it does when disconnected.
- The `DIY` tag in the bundled hardware catalog marks a product line, not how a particular unit was
  assembled. A hand-wired board reporting a commercial hardware model is tagged as that model, so
  FR-012a will hide its GPIO settings from search; they remain reachable by opening the screen.
- Queries shorter than two characters return nothing rather than everything.
- A term matching many entries must order them predictably, including when scores tie.
- A control that is laid out but not currently on screen — hidden behind a toggle that is off — has no
  row to scroll to. The result still navigates; the screen opens at the first visible row of the
  section that control belongs to.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Settings MUST present a search field using the platform's existing search affordance, and
  a non-empty query MUST filter the Settings list in place rather than pushing a separate results view.
- **FR-002**: The index MUST cover the individual controls under Settings — radio configuration, module
  configuration, and app-level screens — not only the 42 screen titles. It currently holds **233
  entries**: 167 generated from the schema and 66 generated from the app-level views.
- **FR-003**: Each entry MUST carry a label and MUST identify the settings destination it belongs to. A
  description and keywords are optional — most settings are adequately named by their label, and prose
  written only to satisfy a schema is worse than none. Matching MUST consider whichever of the three are
  present. Of the 167 schema-backed entries, 144 carry a description and 6 carry keywords.
- **FR-004**: *Not implemented.* The original requirement was that picker option values be indexed, so
  that "Long Fast", "Router" and "United States" would find the controls offering them. They are not:
  an entry matches on its label, keywords and description only. Enum-value metadata is consumed, but by
  the forms (FR-006b), not by search. A client implementing this can index option text as additional
  match text on the entry that owns the picker; this one has not yet.
- **FR-005**: For settings backed by a protobuf field, label, description and keywords MUST be declared
  as `field_metadata` attributes and consumed from generated code — the schema is the single source of
  truth, and a generated registry cannot drift from it. An entry MUST key on **proto message name and
  field tag**, not on any generated language's property name: a field's spelling differs across its
  proto, generated, persisted and view-state forms, and only the tag is stable by contract.
- **FR-005a**: The same registry MUST be what the settings screens themselves render from, not a
  parallel copy. A label that only search reads can be approximate; a label the control wears cannot.
  22 of the 23 configuration screens are rendered this way here.
- **FR-006**: Generated registry code MUST be emitted where the client's localization tooling can see
  it, and MUST key its strings on the field's full proto name rather than on the English. **(iOS only)**
  that means the registry is generated into the app target rather than the protobuf package, because
  string extraction is per-target and a Swift package has no string catalog.
- **FR-006a**: Attributes MUST be scalar, so `keywords` is a single `|`-delimited string that the client
  splits and trims. `|` rather than `,` because a keyword may itself contain a comma.
- **FR-006b**: Picker option text and bitfield flag names MUST come from `enum_value_metadata` on the
  enum value, not from a hand-written copy in the client. A field carries one label, so the ten toggles
  behind `position_flags` are named by the values of the `PositionFlags` enum rather than by the field.
  A client SHOULD hide a deprecated enum value unless it is the value the node currently holds, so a
  node sitting on a retired preset can still see and change it.
- **FR-007**: Every indexed string MUST render in the user's language. *Partly implemented.* Schema
  strings are localized. Matching is against the localized text only — a keyword learned in English does
  not match on a translated device, which the original requirement asked for and the shipped engine does
  not do.
- **FR-008**: Settings with no protobuf field behind them MUST be covered by a catalog of their own, and
  something MUST fail when that catalog goes stale.
- **FR-008a**: **(app-owned)** That catalog is **generated from the settings views** and checked by CI,
  not hand written. It was specified as hand written and shipped generated: a hand-maintained list of
  this size goes stale the moment someone adds a toggle, and a control added without a matching entry is
  not visibly broken — it is just unsearchable. It now holds 68 declarations covering 19 app-level
  screens. Keywords cannot be derived from a view, so the few that earn their place ("psk" for Channels)
  are declared in the generator and merged in. Unit tests cannot run the generator, so the staleness
  check is a CI workflow instead.
- **FR-009**: Documentation pages MUST be searchable from the same field using the existing generated
  documentation index (32 pages), and MUST appear under a section separate from settings results.
- **FR-010**: Matching MUST be case- and diacritic-insensitive, so "prasa" finds "Přáša" and "MQTT"
  finds "mqtt".
- **FR-011**: Results MUST be ranked by where the match landed. The shipped weights are exact label
  1000, label prefix 500, label substring 250, keyword 100, description 50; the label term and the
  others add, so an entry matching in both outranks one matching in either. Equal scores MUST break by
  section order, then label, then destination, so the same query always produces the same list.
- **FR-012**: Results whose screen requires a connected radio MUST remain visible while disconnected,
  visually de-emphasized and labeled as requiring a radio, and MUST still navigate. A managed radio MUST
  be treated the same way: it exposes no configuration, its settings screens render read-only, and a
  result that looks editable when it is not is worse than one that says why.
- **FR-012a**: Results for fields marked `diy_only` MUST be hidden when the connected radio's hardware
  model is not tagged `DIY` in the bundled hardware catalog. Five distinct models carry that tag
  (`DIY_V1`, `HYDRA`, `DR_DEV`, `RPI_PICO`, `NRF52_PROMICRO_DIY`) out of 114, so on a commercial board
  these settings do not appear at all. When no radio is connected, or the catalog cannot be read, the
  hardware is unknown and they MUST be shown rather than hidden on an assumption. Three fields carry
  `diy_only` today, all of them GPS GPIO pins.
- **FR-012b**: `admin_only` is not device-dependent, so hiding it would make those settings permanently
  unfindable. Results for fields marked `admin_only` MUST be shown, de-emphasized in the same way as
  FR-012's disconnected results, with the reason given. No field carries `admin_only` today, so this
  rule is implemented but never exercised.
- **FR-012c**: `deprecated` alone says only *that* a field is superseded. On its own it is not enough to
  decide whether to offer the control, because the replacement's arrival and the old field's removal are
  usually different releases. The schema's rule, stated in `field_metadata.proto`, is:

  - Below `deprecated_since`, **show the field** — firmware on that node still acts on it.
  - At or above `deprecated_since`, treat it as `deprecated` does.
  - A field with `deprecated` and no `deprecated_since` has no version to compare, so `deprecated`
    applies everywhere.

  The two consumers in this app read it differently, and only one of them is right:

  - **The settings forms** omit a field the target node's firmware does not read — below
    `since_firmware` or at/above `deprecated_since` — because a control the radio ignores is a control
    that does nothing. A node whose firmware version the app has never seen shows everything; the
    version compared is the *target* node's, which under remote administration is not the connected
    radio's.
  - **Search** shows a `deprecated` entry de-emphasized and marked, and does not consult the firmware
    window at all. Search is a deliberate act: someone who types the name is better answered by "this
    exists and is deprecated" than by nothing. This is a gap, not a decision — the search engine
    predates the two version attributes and has not been revisited.

  An earlier draft said "hidden unless the radio currently holds that value". That is the wrong test
  even where per-field node state is available: firmware force-writes some deprecated fields —
  `canned_message.enabled` is set true from 2.7.4 — so "holds a non-default value" would show those
  rows on every modern radio. The version is the right question.
- **FR-012d**: `since_firmware` is the first release that reads a field. A client rendering a control for
  a field the node's firmware does not have offers a setting that will be ignored; one hiding a field the
  node does have takes away a setting that works. A client SHOULD hide the control below
  `since_firmware`, and MUST show it when the node's firmware version is unknown. The same attribute on
  `ModuleConfig`'s own fields gates whether a module's screen is offered at all, which is how the app
  stopped keeping a version constant per module in its own source.
- **FR-013**: Navigation MUST route through the existing settings navigation state so deep links and
  search results share one path. **Selecting a result MUST open the screen and scroll to the control it
  named.** The original requirement said the opposite — open the screen only — on the grounds that
  per-control anchors would be needed on every configuration screen. Driving those screens from the
  schema supplied the anchors as a side effect, so it was revisited. Where the control is laid out but
  not currently visible, the screen lands on the first visible row of its section; where the screen is
  not schema-driven, it simply opens.
- **FR-014**: Result rows MUST meet the 44×44 point minimum touch target and MUST remain legible at the
  largest Dynamic Type size without clipping.
- **FR-015**: The index MUST be provably complete, not merely valid. A test MUST fail when a field in the
  configuration protobufs is neither indexed nor named on an exemption list carrying a stated reason,
  and representative screens MUST pin their expected entry count — otherwise a newly added control is
  simply absent from search, which no test that only validates existing entries can detect. The
  authoritative list of fields is the **protobuf source text**, not the generated registry, which holds
  only the fields that carry an annotation.
- **FR-015a**: The exemption list is the fields with no label to give. There are 203 fields across the 24
  messages that map to a settings screen; 167 carry a label. Of the remaining 36:

  - **28 are exempt**, in two groups. *No control at all*, whether saved-but-unexposed (`ls_secs`,
    `min_wake_secs`, `sds_secs`, `frequency_offset`), not user-facing (`ipv4_config`,
    `broadcast_targets`), or simply not offered by this client yet (`buzzer_mode`, `ipv6_enabled`, the
    health telemetry fields). And *a label the client renders from a value rather than a literal*,
    such as `position_precision` behind a slider. Adding to the list requires stating which group a
    field belongs to.
  - **8 are deprecated and unlabeled**, which is a rule rather than a list: a deprecated field with no
    label has nothing to render and nothing to match, so it is skipped without an exemption entry.

  Eight of the 28 are the subject of [#1106](https://github.com/meshtastic/protobufs/pull/1106) and will
  leave the list when it merges.

  Two things are explicitly NOT reasons to exempt: that a label extractor could not find one — a control
  in a nested view or behind a computed binding still has a label — and that the on-screen label is
  interpolated. Where the interface renders a label from a value, the schema MUST carry the stable name
  and the unit separately rather than the assembled string: `tx_power` is "Transmit Power" with a unit
  of `dBm`, not "12 dBm Transmit Power". `red`, `green` and `blue` are named individually even
  though the app presents them as one color picker, and carry `color|colour|rgb|led|ambient|lighting`
  so that "color" finds them.

  The exemption list in the test names 37 fields, nine more than are load-bearing: `private_key`,
  `public_key`, `admin_key`, `position_flags`, `gps_mode`, `ignore_incoming`, `override_duty_cycle`,
  `pa_fan_disabled` and `wait_bluetooth_secs` have since been labeled upstream and their entries are
  now inert.
- **FR-016**: **(iOS only)** Any string the index needs that bypasses the string catalog MUST be migrated
  into it. Partly done: the interval picker labels were converted, and 204 sites in `Meshtastic/Enums/`
  now use `String(localized:)`. 123 literal `.localized` sites remain, all on proto-backed enums —
  region names, device roles, modem presets — whose text the schema now carries. Replacing those
  properties with registry lookups is the deferred cleanup, not a blocker.
- **FR-017**: **(app-owned)** `FieldMetadata` has no `section`, `order` or field-dependency attribute.
  Which fields sit together, in what order, and that "Fixed Pin" only matters while the pairing mode is
  fixed-PIN, are decisions every client has to make for itself and nothing keeps them in step. The iOS
  reference implementation keeps them in a per-screen overlay in Swift — see
  `Meshtastic/Views/Settings/Config/Forms/ConfigFormOverlay.swift` and the per-screen files beside it —
  deliberately holding no display text, so a field the schema renames fails to compile rather than
  failing to render. Its tests assert that every renderable field of a message is either laid out or
  omitted with a reason, and flag any overlay entry that restates something the schema could say. If a
  section or order attribute is ever added upstream, those entries become redundant and should go.

### Key Entities

- **Search entry**: one indexed control or screen. Carries a label, an optional description, keywords, a
  destination, the Settings list group it belongs to, the proto field identity if it has one, and
  whether it needs a connected radio.
- **Field identity**: proto message full name plus field tag. The join key between an entry and the
  generated registry, and between a search result and the row a form should scroll to.
- **Field metadata**: schema-declared attributes on a protobuf field or enum value, read by both search
  and the settings forms.
- **Curated entry**: a generated entry for a setting with no protobuf field, with no field identity.
- **Documentation entry**: an existing indexed documentation page, reused unchanged.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Searching "hops", "psk", "transmit power" and "region" each returns the intended control
  in the top five results, asserted by a query corpus in the tests. "Long Fast" is not among them: option
  values are not indexed (FR-004).
- **SC-002**: Every field of every configuration message that maps to a settings screen is either
  indexed or exempt with a stated reason, enforced against the protobuf source text rather than the
  generated registry. Findability is measured by the query corpus above, which grows whenever a search
  that should have worked did not — not by requiring every entry to carry a keyword or description,
  which would mean inventing synonyms for settings whose label already says what they are.
- **SC-003**: A setting's label cannot drift from its entry. For schema-backed settings this is
  structural — both come from the same annotation. For app-level settings the catalog is regenerated
  from the views and a CI job fails when the committed file differs.
- **SC-004**: No indexed string renders in English when the device is set to a translated language,
  except the proto-backed enum option values still served by the app's own enums (FR-016).
- **SC-005**: Searching while disconnected returns the same settings results as when connected, each
  marked as needing a radio.
- **SC-006**: A user who knows a feature's common name but not its location reaches it in one search and
  one tap, landing on the control rather than the top of its screen.

## Clarifications

### Session 2026-09-13

- **Index granularity**: every individual setting, not only the 42 screen titles.
- **Coverage**: everything under Settings, including app-level screens, not only radio and module
  configuration.
- **Documentation**: searchable from the same field.
- **Result layout**: settings and documentation in separate sections, settings first.
- **Picker option values**: indexed, so option names like "Long Fast" are findable.
- **List behavior**: the Settings list filters in place; no separate results screen.
- **Disconnected**: radio-configuration results are shown dimmed with an explanation, deliberately
  differing from the Settings list, which hides those sections entirely.
- **Index source**: generated from `meshtastic.field_metadata` where a protobuf field exists; curated
  only for settings that have none.
- **Localized strings**: labels, descriptions and keywords all belong in the string catalog, so
  proto-declared strings must reach it rather than bypassing it.
- Q: How should a missing index entry be caught — a control that exists but was never indexed? →
  A: A test asserting every configuration protobuf field carries `field_metadata`, plus a pinned
  entry count per curated screen.
- Q: Picker option values never reach the string catalog, contradicting FR-007. How is that resolved?
  → A: Migrate them into the catalog as part of this feature, along with the interval picker labels
  that bypass it the same way.
- Q: What determines result order? → A: Field-weighted — exact label, label prefix, keyword, then
  description or option value — with ties broken by section order and then label.
- Q: If #952 slips, what does 019 do? → A: Open a second protobufs change branched from #952 carrying
  the annotations for every configuration field, so the app can be built end to end against a real
  generated registry rather than waiting or writing throwaway entries.
- Q: When a result is a single control, what happens on arrival at its screen? → A: Open the screen
  only; no scrolling to or highlighting of the individual control.

**Refined by Phase 0 research.** The decisions above stand. Two are sharper now:

The **completeness** answer becomes "every field is indexed or exempted with a reason" rather than
"every field carries `field_metadata`". A field maps to any number of controls in both directions —
`position_flags` is one field behind ten toggles, `json_enabled` has no control at all — so a strict
one-entry-per-field rule would be wrong. The authoritative list of fields is the protobuf source
text, not the generated registry, which holds only annotated fields.

The **localized strings** decision needed work upstream to be true. String attributes were emitted
as bare Swift literals that Xcode's extractor cannot see, which would have left every label
permanently English. Fixed in meshtastic/protobufs#952 (`20fadc6`): both generators now emit
`String(localized:defaultValue:comment:)` keyed by the field's full proto name. That work also
required the registry be generated into the app target rather than the `MeshtasticProtobufs`
package, since a SwiftPM package has no string catalog. See [research.md](./research.md) D1 to D3.


### Session 2026-09-13 (post-upstream)

- Q: Are the fields that annotation skipped still findable in search, or absent from it? →
  A: The question dissolved — nothing with a control is skipped any more. A control whose label the
  app interpolates, or whose binding the extractor could not follow, gets a hand-written annotation
  instead of an exemption. Twelve fields were recovered by fixing the extractor (`bandwidth`,
  `coding_rate`, `channel_num`, the Audio I2S pins, the PaxCounter thresholds) and five annotated by
  hand (`tx_power`, `red`, `green`, `blue`, `current`). The exemptions that remain are fields with no
  control at all, which are correctly absent from search — 37 once the completeness test ran against
  a real registry and surfaced the firmware settings this client does not offer yet.
- Q: Where do the app-level entries live, given they have no schema? → A: A single curated Swift
  file, same entry shape, `String(localized:)` text, `field: nil`. Not declarations beside each view,
  which would scatter the index; not generated, since with no schema behind them the generated file
  would be the source of truth and nothing would enforce regenerating it.
- Q: Should deprecated settings appear in results? → A: Shown, de-emphasized and marked. The first
  answer was "hidden unless the radio currently holds that value", which review showed could not be
  implemented — the index has no per-field node state — and whose half-built form hid every
  deprecated setting, the opposite of the intent.
- Q: How should `diy_only` and `admin_only` affect results, given the app has no direct signal for
  how a board was built? → A: Hide `diy_only` results unless the connected hardware model is
  `DIY`-tagged in `DeviceHardware.json`; show them when disconnected, since the hardware is unknown.
  `admin_only` is shown de-emphasized rather than hidden, because it marks a class of setting rather
  than a class of device and hiding it would make those settings unfindable.
- Q: SC-002 required every entry to carry a keyword or description, which 248 of 318 entries do not.
  How is that resolved? → A: Make the criterion match reality. Not everything will have keywords.
  Coverage stays enforced by FR-015 against the protobuf source; findability moves to a corpus of
  terms a user would plausibly type, asserted to return the intended control, which grows whenever a
  search that should have worked did not. FR-003 correspondingly requires only a label, with
  description and keywords optional.

### Session 2026-09-20

Written after re-reading the shipped code and the current protobufs, for another client's team to
implement against. Everything below is a correction to what is above it, not a new decision.

- **The registry now drives the settings UI, not only search.** 22 of the 23 configuration screens
  render from it. Labels, descriptions, units, bounds and the two firmware attributes are what the user
  reads on the control, so an approximate label is no longer harmless. Recorded as FR-005a. This is
  also why [#1107](https://github.com/meshtastic/protobufs/pull/1107) mattered and why its closure is
  worth flagging: eighteen labels are still sentences where a control name belongs.
- **`deprecated_since` supersedes the old FR-012c.** `deprecated` on its own was never enough to decide
  whether to offer a control, because firmware usually keeps honoring a field for several releases after
  its replacement lands. FR-012c now states the schema's rule and, honestly, records that the two
  consumers in this app apply it differently — the forms respect the firmware window, search does not.
  Search not consulting it is a gap, not a design choice.
- **`since_firmware` replaced per-module version constants in app code.** Recorded as FR-012d. On
  `ModuleConfig`'s own fields it also gates whether a module screen is offered at all.
- **Results land on the control.** FR-013 said explicitly that they would not. Making the screens
  schema-driven produced per-row anchors as a side effect, so the reason for the original decision
  disappeared and it was reversed in #2512 and #2514.
- **The app-level catalog is generated, not hand written.** FR-008a said the opposite, on the reasoning
  that a generated file with no schema behind it would become its own source of truth. It is generated
  from the views — which *are* the source of truth for controls that exist only in the app — and a CI
  job fails when it is stale.
- **Option values are not indexed.** FR-004 was never implemented. Enum-value metadata is consumed by
  the pickers, not by the matcher, so "Long Fast" does not find the Presets control. SC-001's example
  list was wrong and has been replaced with the corpus the tests actually assert.
- **Counts corrected.** The schema carries 187 field and 186 enum-value annotations, not 155 and 122.
  The index holds 233 entries. 28 fields are genuinely unlabeled and exempt, not 37; the test's list has
  nine inert entries left over from before those fields were labeled.
- **Sections, field order and field dependencies have no home in the schema.** Recorded as FR-017. This
  is the largest thing two clients can diverge on without either being wrong, and nothing detects it.

## Dependencies

- `meshtastic/protobufs`, pinned as a submodule. The schema is the critical path: search cannot index
  labels that do not exist, and a schema-driven form cannot render a field that has none.
- The generated documentation index, built from the documentation pages themselves so it cannot describe
  a page that is not there.

## Assumptions

- `FieldMetadata` attributes must be scalar; `repeated` is rejected at generation time. A keyword list is
  therefore a single string, delimited with `|` — chosen over `,` because a keyword may itself contain a
  comma — which the client splits and trims.
- Not every control maps to a protobuf field, and the relationship is not one-to-one in either direction.
  `coding_rate` is one field behind a preset toggle and an override control, and the LoRa screen renders
  it with a hand-written control rather than a generic one; `frequency_offset` has no control at all.
  Interface-only affordances such as "Use Preset" and every app-level screen stay outside the schema.
- Absence of an annotation is not a signal. A field with no registry entry means "nothing was said", never
  "not DIY-only" or "not deprecated".
- Labels are unique within a message and within an enum — generation fails otherwise — so
  (screen, label) distinguishes entries on the same screen. Across messages they repeat freely.
- `keywords` is annotated only where the label cannot carry the term. It cannot be seeded from a client,
  and generating synonyms mechanically would be guessing; labels and descriptions already hold the words
  a user is most likely to type, and "hops" is inside "Hop Limit". It earns its place when nothing is
  named what the user searches for: `red`, `green` and `blue` carry `color|colour|rgb|led|ambient|lighting`
  because the app shows them as one color picker and no field is called that. The whole schema carries seven keyword
  annotations: six on fields (`hop_limit`, `tx_power` and the four ambient-lighting ones) and one on a
  modem preset enum value, which search does not read. Ranking weights a keyword hit below a label
  hit, so a sparse set costs nothing.
- Annotating surfaced schema values this client does not offer at all — a region code, two OLED variants,
  several serial modes. They are newer than the client. They will not appear until it adds the
  corresponding cases, which is a separate gap.
- `unit`, `min_value` and `max_value` are presentation metadata, not a wire contract. Nothing enforces
  them on receipt; the firmware remains the source of truth and a bound should be stated only where the
  firmware genuinely enforces it.
- Settings screens render their own read-only state when no radio is connected, so a search result may
  navigate to any screen without special handling.

## Out of Scope

- Searching anything outside Settings — nodes, messages and map features have their own search.
- Changing a setting's value directly from a result row.
- Search history, recent searches, or suggestions.
- Fuzzy or typo-tolerant matching beyond prefix matching.
