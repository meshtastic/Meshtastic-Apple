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
  declared as `meshtastic.field_metadata` attributes in the schema and consumed from generated code —
  the schema is the single source of truth, and a generated registry cannot drift from it.
- **FR-006**: Generated registry code MUST be emitted where the app's string catalog can see it, and
  MUST emit its strings as literal localized-string expressions — `MeshtasticProtobufs` is a separate
  package with no catalog of its own, so a registry generated into it would never reach translators.
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
- **FR-011**: Results MUST be ranked by relevance, with a deterministic order for equal scores so the
  same query always produces the same list.
- **FR-012**: Results whose screen requires a connected radio MUST remain visible while disconnected,
  visually de-emphasised and labelled as requiring a radio, and MUST still navigate.
- **FR-013**: Navigation MUST route through the existing settings navigation state so deep links and
  search results share one path.
- **FR-014**: Result rows MUST meet the 44×44 point minimum touch target and MUST remain legible at
  the largest Dynamic Type size without clipping.

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
- **SC-002**: Every control under Settings is findable by at least one term that is not its exact
  label — verified by a test asserting each entry carries at least one keyword or description.
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

## Dependencies

- **meshtastic/protobufs#952** introduces `field_metadata.proto` and the code generators, including a
  Swift generator. It is approved and mergeable but its build is failing, and the submodule here does
  not yet contain `field_metadata.proto`. Adding attributes is documented as a schema-only change, so
  no generator work is expected once it lands, subject to the scalar constraint below.
- The documentation index at `Meshtastic/Resources/docs/index.json`, generated by
  `scripts/build-docs.sh`.

## Assumptions

- `FieldMetadata` attributes must be scalar; `repeated` is rejected at generation time. A keyword list
  is therefore a single delimited string, and the delimiter must be specified in the plan.
- Not every control maps to a protobuf field. User-interface-only affordances such as "Use Preset",
  and every app-level screen, have no field and stay curated. Roughly 201 of 269 controls are
  proto-backed on current counts.
- Picker option values come from enumerations that localize at runtime through a mechanism the string
  extractor cannot see, so those values are absent from the catalog today. Making FR-007 true for
  option values requires moving them into the catalog, which the plan must account for.
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
