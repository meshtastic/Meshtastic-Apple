# Feature Specification: Settings Search

**Feature Branch**: `019-settings-search`
**Created**: 2026-09-13
**Status**: Draft — approved direction, not yet implemented
**Input**: User description: "a settings search view to help users find features similar to how settings search works on iOS and Mac", extended to cover every individual setting, the in-app documentation, and generation of the index from protobuf field metadata.

## Overview

Settings has grown to 42 destinations and roughly 269 individual controls across 25 configuration
screens. A user who knows a feature exists frequently cannot find which screen holds it — hop limit
is on LoRa, pre-shared keys are on Channels, and nothing in the interface says so. iOS and macOS
answer this with a search field at the top of Settings.

The search covers three kinds of result: the settings screens themselves, the individual controls on
them, and the in-app documentation pages. Typing filters the Settings list in place rather than
pushing a separate results screen.

The index for radio and module settings is **generated from protobuf field metadata**, not hand
written, so it cannot drift from the schema it describes. App-level settings that have no protobuf
field behind them are curated, and a test keeps that remainder honest.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find a setting without knowing its screen (Priority: P1)

A user wants to change how many times their messages are repeated across the mesh. They know the
word "hops". They open Settings, type it, and get the control itself — not just a screen to go
hunting through.

**Why this priority**: This is the feature. Everything else is elaboration on it.

**Independent Test**: Type "hops" in Settings and confirm a result identifying the hop-limit control,
the screen it lives on, and its section; tapping it opens that screen.

**Acceptance Scenarios**:

1. **Given** the Settings list, **When** the user types "hops", **Then** a result appears showing the
   LoRa `Number of hops` control with "LoRa" and "Radio Configuration" as its breadcrumb.
2. **Given** a result is shown, **When** the user taps it, **Then** the app navigates to that settings
   screen through the existing router.
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
2. **Given** a documentation result, **When** the user taps it, **Then** the relevant page opens.
3. **Given** a query matching only documentation, **Then** only the documentation section is shown —
   empty sections never render.

---

### User Story 3 - Discover a feature while disconnected (Priority: P3)

A user without a radio connected searches for a feature to learn whether the app supports it at all.

**Why this priority**: Knowing a capability exists is most of the value of search, and the Settings
list currently hides the entire configuration tree when no radio is connected, so search is the only
way to discover it.

**Independent Test**: With no radio connected, search a radio-configuration term and confirm the
result is listed, visibly de-emphasised, with an explanation.

**Acceptance Scenarios**:

1. **Given** no connected radio, **When** the user searches a radio-configuration term, **Then** the
   result is shown dimmed with a note that it needs a connected radio.
2. **Given** such a result is tapped, **Then** the app still navigates to the screen, which presents
   its existing "Please connect to a radio to configure settings" state rather than an error.

---

### Edge Cases

- A control whose visible label is generic — "Enabled" appears on six different screens — is
  distinguishable only by its screen and section, so those form part of its identity rather than
  decoration.
- A control with no static label at all, such as the segmented GPS mode picker, cannot be indexed by
  label and must be reached by its section heading or its accessibility label.
- A module excluded on the connected node, or requiring newer firmware, is absent from the Settings
  list but still present in the index — the index is static while the list is node-dependent.
- A managed radio shows no configuration sections; search behaves as it does when disconnected.
- Queries shorter than two characters, or consisting only of punctuation, return nothing rather than
  everything.
- A term matching many entries must order them predictably, including when scores tie.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Settings MUST present a search field using the app's existing search affordance, and a
  non-empty query MUST filter the Settings list in place rather than pushing a separate results view.
- **FR-002**: The index MUST cover every individual control under Settings — radio configuration,
  module configuration, and app-level screens — not only the 42 screen titles.
- **FR-003**: Each entry MUST carry a label, a plain-language description, and search keywords, and
  MUST identify the settings destination and section it belongs to. Matching MUST consider all three
  text fields, because the description is where a user's own wording is most likely to appear.
- **FR-004**: Picker option values MUST be indexed, so "Long Fast", "Router" and "United States" find
  the controls that offer them.
- **FR-005**: For settings backed by a protobuf field, label, description and keywords MUST be
  declared as `meshtastic.field_metadata` attributes and consumed from generated code — the schema
  is the single source of truth, and a generated registry cannot drift from it. The entry MUST key
  on proto message name and tag, not on any Swift name: a field's spelling differs across its proto,
  generated, entity and view-state forms, and only the tag is stable by contract.
- **FR-006**: Generated registry code MUST be emitted where the app's string catalog can see it, and
  MUST emit its strings as localized-string expressions keyed by the field's full proto name. String
  attributes that render as bare literals never reach translators, and a catalog keyed by the
  English would collapse the six different controls labelled "Enabled" onto one translation.
- **FR-006a**: Attributes MUST be scalar, so `keywords` is a single `|`-delimited string that the
  app splits and trims.
- **FR-006b**: Picker option values and bitfield flags MUST take their display text from
  `meshtastic.enum_value_metadata` on the enum value, not from a hand-written copy in the app. A
  field carries one label, so the ten toggles behind `position_flags` are named by the values of the
  `PositionFlags` enum rather than by the field. Where a single field genuinely backs several
  controls with no enum behind them — `coding_rate` behind a preset toggle and two sliders — those
  controls MUST stay curated on the exemption list FR-015 defines.
- **FR-007**: Every indexed string MUST appear in `Localizable.xcstrings` and MUST render in the
  user's language. Keywords MUST match against both the user's language and the English source, so a
  term learned from English documentation still finds its setting.
- **FR-008**: Settings with no protobuf field behind them MUST be covered by a curated catalogue, and
  a test MUST fail when an entry names a destination that does not exist or a label that no longer
  appears in the screen it claims. Controls with no static label MUST be listed as explicit,
  enumerated exemptions rather than silently skipped.
- **FR-009**: Documentation pages MUST be searchable from the same field using the existing generated
  documentation index, and MUST appear under a section separate from settings results.
- **FR-010**: Matching MUST be case- and diacritic-insensitive, so "prasa" finds "Přáša" and "MQTT"
  finds "mqtt".
- **FR-011**: Results MUST be ranked by where the match landed, in the order exact label, label
  prefix, keyword, then description or option value. Equal scores MUST break by section order and
  then label, so the same query always produces the same list — a match in a control's own name is
  what a user expects first, regardless of how many keywords a rival entry carries.
- **FR-012**: Results whose screen requires a connected radio MUST remain visible while disconnected,
  visually de-emphasised and labelled as requiring a radio, and MUST still navigate.
- **FR-013**: Navigation MUST route through the existing settings navigation state so deep links and
  search results share one path. Selecting a result MUST open the screen holding that control and
  nothing further — no scrolling to or highlighting of the individual control, which would require
  per-control anchors on all 25 configuration screens and has no defined behaviour for the controls
  that carry no stable identity.
- **FR-014**: Result rows MUST meet the 44×44 point minimum touch target and MUST remain legible at
  the largest Dynamic Type size without clipping.
- **FR-015**: The index MUST be provably complete, not merely valid. A test MUST fail when a field in
  the configuration protobufs is neither indexed nor named on an exemption list carrying a stated
  reason, and each screen MUST pin its expected entry count — otherwise a newly added control is
  simply absent from search, which no test that only validates existing entries can detect. The
  authoritative list of fields is the protobuf source text, not the generated registry, which holds
  only the fields that carry an annotation.
- **FR-016**: Any string the index needs that currently bypasses the string catalog MUST be migrated
  into it as part of this feature. Two known groups qualify: the enumeration values behind picker
  options, which localize at runtime through a mechanism the extractor cannot see, and the interval
  picker labels, which pass through a `String` parameter that binds the non-localizing overload.
  Neither translates today, so this fixes an existing defect rather than only serving search.

### Key Entities

- **Search entry**: one indexed thing — a control, a screen, or a documentation page. Carries a
  label, a description, keywords, a destination, a section, and whether it needs a connected radio.
- **Field metadata**: schema-declared attributes on a protobuf field, from which entries for
  proto-backed settings are generated.
- **Curated entry**: a hand-written entry for a setting with no protobuf field, constrained by the
  drift test.
- **Documentation entry**: an existing indexed documentation page, reused unchanged.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Searching "hops", "psk", "duty cycle" and "Long Fast" each returns the correct control
  as the first settings result.
- **SC-002**: Every control under Settings is indexed, and findable by at least one term that is not
  its exact label — completeness enforced by FR-015 rather than assumed, and findability verified by
  a test asserting each entry carries at least one keyword or description.
- **SC-003**: Renaming a setting's label without updating its entry fails a test, demonstrated by
  performing the rename and observing the failure before reverting.
- **SC-004**: No indexed string is missing from `Localizable.xcstrings`, and none renders in English
  when the device is set to a translated language.
- **SC-005**: Searching while disconnected returns the same settings results as when connected, each
  marked as needing a radio.
- **SC-006**: A user who knows a feature's common name but not its location reaches it in one search
  and one tap, from any Settings screen.

## Clarifications

### Session 2026-09-13

- **Index granularity**: every individual setting, not only the 42 screen titles.
- **Coverage**: everything under Settings, including app-level screens, not only radio and module
  configuration.
- **Documentation**: searchable from the same field.
- **Result layout**: settings and documentation in separate sections, settings first.
- **Picker option values**: indexed, so option names like "Long Fast" are findable.
- **List behaviour**: the Settings list filters in place; no separate results screen.
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

## Dependencies

- **meshtastic/protobufs#952** introduces `field_metadata.proto` and the code generators, including
  `tools/protoc-gen-fieldmeta-swift`. As of 2026-09-13 it is open and mergeable, and now also
  carries the `label`, `description` and `keywords` attributes, localized string emission, and fixes
  for two generator bugs those attributes exposed (`20fadc6`). The submodule here does not yet
  contain `field_metadata.proto`.
- A second protobufs change, branched from #952, MUST carry the annotations themselves — label,
  description and keywords across the configuration and module configuration fields, roughly 201 of
  221. #952 supplies the mechanism; this supplies the data. Branching rather than waiting lets the
  app be built and tested end to end against a real generated registry, and the annotations are the
  permanent deliverable, so nothing is thrown away when #952 merges and the branch rebases.
- This is the critical path: search cannot index labels that do not exist yet.
- The documentation index at `Meshtastic/Resources/docs/index.json`, generated by
  `scripts/build-docs.sh`.

## Assumptions

- `FieldMetadata` attributes must be scalar; `repeated` is rejected at generation time. A keyword
  list is therefore a single string, delimited with `|` — chosen over `,` because a keyword may
  itself contain a comma — which the app splits and trims.
- Not every control maps to a protobuf field, and the relationship is not one-to-one in either
  direction. `position_flags` is a single field behind ten toggles; `coding_rate` backs three
  controls; `json_enabled`, `frequency_offset` and `override_duty_cycle` have no control at all.
  User-interface-only affordances such as "Use Preset" and every app-level screen stay curated.
  There are 221 configuration fields across 29 messages, nine of them already deprecated.
- Migrating the remaining enumeration values and interval picker labels into the catalog (FR-016)
  covers the 192 of 319 literal `.localized` sites in `Meshtastic/Enums/` that have no protobuf
  behind them — `IntervalType`, `RoutingError`, `ActivityType`, `FirmwareEditions` and the app
  settings enums. The other 127, including all 37 region names, come from the schema under FR-006b.
  It changes what every non-English user sees independently of search, so it ships as its own pull
  request.
- The existing `unit`, `min_value`, `max_value`, `diy_only` and `admin_only` attributes are useful to
  search beyond labelling — a unit gives a searchable term, and the two boolean attributes can
  explain why a setting is absent on a given radio.
- Settings screens render their own disabled state when no radio is connected, so a search result may
  navigate to any screen without special handling.

## Out of Scope

- Searching anything outside Settings — nodes, messages and map features have their own search.
- Changing a setting's value directly from a result row.
- Search history, recent searches, or suggestions.
- Fuzzy or typo-tolerant matching beyond prefix matching on keywords.
