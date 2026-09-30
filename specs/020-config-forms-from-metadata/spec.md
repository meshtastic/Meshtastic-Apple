# Feature Specification: Config Forms From Field Metadata

**Feature Branch**: `020-config-forms-from-metadata`

**Created**: 2026-09-20

**Status**: Implemented for 22 of 24 radio configuration screens; see Progress

**Input**: Radio configuration screens should render from the protobuf field metadata
rather than from labels and controls written into each screen, so display text is shared
between clients and a newly annotated field reaches the app without a screen edit.

## Audience

Written for maintainers of this repository and for the other Meshtastic client teams.
Anything that is a property of the schema, or a rule a client has to apply, is stated as
such. Anything that is specific to this app is marked **(iOS only)** so another client
knows not to copy it — and, more usefully, knows where the two clients are free to
diverge without anything detecting it.

## Overview

Before this feature, each of the 24 radio configuration screens hand-wrote every label,
description, section heading, control choice and firmware gate. The same setting was
named independently in the iOS app, the Android app and the web client, and the same
firmware version boundary was written into each of them as a constant. A field added to
the protobufs reached a screen only when somebody edited that screen.

Spec 019 put `FieldMetadata` annotations upstream and generated a registry into the app,
but only settings search consumed it. This feature makes the configuration screens
themselves read from it: a screen now supplies **layout** (which fields, in what order,
grouped how, shown when) and the schema supplies **everything the user reads**.

The split matters more than the mechanism:

| concern | owner |
|---|---|
| label, description, unit, bounds, deprecation, firmware window, search keywords | the schema, shared by every client |
| which fields a screen shows, their order, their grouping, which control edits them | the client |
| hardware and regulatory gates the schema cannot express | the client |

## Progress

Delivered across eleven pull requests on `main`:

| screens | PR |
|---|---|
| External Notification, Serial, Neighbor Info | #2505 |
| Bluetooth, PAX Counter, Store & Forward, Range Test | #2507 |
| Telemetry, Display, Ambient Lighting, Device | #2508 |
| Power, Traffic Management, MQTT, Canned Messages | #2510 |
| Position | #2521 |
| Audio, Detection Sensor | #2519 |
| TAK | #2525 |
| Network | #2526 |
| Security | #2528 |
| LoRa | #2529 |
| Duty cycle override, PA fan, Bluetooth wait (first fields added by annotation) | #2530 |

22 messages render from the schema. Two do not, by decision rather than omission:

- `ModuleConfig.MeshBeaconConfig` — a `repeated broadcast_targets` editor and channel
  resolution that no generic control covers.
- `ModuleConfig.MapReportSettings` — not a screen of its own; nested in MQTT and laid out
  there through its flattened fields.

`RtttlConfig` is not a config message and is out of scope entirely.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Only see settings this radio actually has (Priority: P1)

An operator opens a configuration screen. Every control shown is one the connected
firmware reads. A setting their firmware is too old for is absent rather than present and
silently ignored; a setting newer firmware stopped honouring is absent rather than
appearing to work.

**Why this priority**: A control that does nothing is worse than a missing one — the
operator changes it, saves, sees no error, and believes the radio is configured. This is
the failure the firmware-window attributes exist to prevent, and it is the one thing the
schema can state that no client can work out for itself.

**Independent Test**: Connect radios on two firmware versions that straddle a field's
`since_firmware`. The older shows no control; the newer does. No version number appears
in screen code.

**Acceptance Scenarios**:

1. **Given** a field annotated `since_firmware: "2.7.13"` and a radio on 2.7.12, **When**
   the operator opens that screen, **Then** the control is absent.
2. **Given** the same field and a radio on 2.7.13, **When** the operator opens that
   screen, **Then** the control is present.
3. **Given** a field annotated `deprecated_since: "2.8.0"` and a radio on 2.7.19,
   **When** the operator opens that screen, **Then** the control is present, because that
   firmware still reads it.
4. **Given** the same field and a radio on 2.8.0, **When** the operator opens that
   screen, **Then** the control is absent.
5. **Given** a radio whose firmware version the app has not learned, **When** the operator
   opens any screen, **Then** every control is shown, because hiding a working setting is
   the worse error.

---

### User Story 2 - The same setting says the same thing everywhere (Priority: P2)

An operator who has used another Meshtastic client, or read the documentation, finds the
setting named the way they expect. An operator using the app in their own language reads
a translation that was made once, for the schema, rather than separately per client.

**Why this priority**: This is the shared-vocabulary payoff. It does not change what the
radio does, which is why it sits below US1, but it is the reason the metadata exists.

**Independent Test**: Change a label upstream, bump the submodule, regenerate. The screen
text changes with no screen edit, and settings search changes with it.

**Acceptance Scenarios**:

1. **Given** a field whose label is corrected upstream, **When** the submodule is bumped
   and the registry regenerated, **Then** the screen renders the new wording with no edit
   to the screen.
2. **Given** a field that gains a `description` upstream, **When** the registry is
   regenerated, **Then** the screen shows helper text under the control that was not there
   before, with no edit to the screen.
3. **Given** a field with `unit: "s"` and no explicit control, **When** the screen
   renders, **Then** it offers an interval picker rather than a raw number field.

---

### User Story 3 - A newly annotated field reaches the app without a new screen (Priority: P3)

A maintainer wants to offer a setting the app has never shown. If the field is already
annotated and already stored, the work is one line of layout, not a new view.

**Why this priority**: The maintenance argument. Real, and demonstrated by #2530, but it
benefits contributors rather than operators.

**Independent Test**: Add a layout entry for a labelled field that round-trips through
its entity. It renders, saves and reloads with no other change.

**Acceptance Scenarios**:

1. **Given** a labelled field that the entity stores, **When** a layout entry is added,
   **Then** it renders with schema text and saves without further code.
2. **Given** a labelled field the entity does **not** store, **When** a layout entry is
   added, **Then** the change is incomplete: the control would show a default on a radio
   that holds a different value and write that default back on save. Entity storage is
   part of offering the field.
3. **Given** a field with no label upstream, **When** somebody tries to lay it out,
   **Then** validation fails and names the field, because there is no text to render.

---

### Edge Cases

- **A field with no label.** Cannot be rendered. It must be listed as omitted with a
  reason, so the gap is recorded rather than invisible.
- **An enum value from newer firmware than the app knows.** The picker must still show a
  row matching the stored value; silently substituting a different one would rewrite the
  radio's setting on the next save.
- **A deprecated field the radio still holds a non-default value for.** Hiding it hides a
  setting that is actually in effect. Showing it invites re-enabling something dead.
- **Remote administration.** The gateway radio and the target node can be on different
  firmware. Every firmware window must be resolved against the **target** node.
- **A regulatory or hardware constraint the schema cannot state.** Duty cycle by region,
  a fan that only four boards have, an ESP32-only sleep timer. These cannot come from the
  schema and must not be guessed.
- **Hardware the app has not identified.** Hide the control rather than assume. A
  wrongly offered control writes a value nothing reads.
- **A field the entity does not persist.** Loading produces the proto default regardless
  of what the radio holds, so offering a control for it silently overwrites.
- **A save that fails.** The operator must be told. Logging alone was the prior behaviour
  and is not sufficient.

## Requirements *(mandatory)*

### Functional Requirements

#### Display text

- **FR-001**: Every label, description, unit and numeric bound a configuration screen
  renders MUST come from the field metadata registry. A screen MUST NOT hard-code any of
  them.
- **FR-002**: A field with no `label` MUST NOT be rendered. Laying one out is a
  validation failure, not a fallback to the field name.
- **FR-003**: Every field of every migrated message MUST be either laid out exactly once
  or listed as omitted **with a reason**. There is no third state. Deprecated-and-
  unlabelled fields are exempt by rule rather than by list.
- **FR-004**: Omission reasons MUST say why the field is not offered, and MUST be
  accurate. "Not offered by this client" and "unlabelled upstream" are different
  statements and are not interchangeable.

#### Firmware windows

- **FR-005**: A field annotated `since_firmware` MUST be hidden on firmware below that
  version. A field annotated `deprecated_since` MUST be hidden at or above that version.
- **FR-006**: Both MUST be resolved against the firmware of the **node being configured**,
  not the connected gateway, so remote administration gates correctly.
- **FR-007**: When the target node's firmware version is unknown, every field MUST be
  shown. An unknown version is not a reason to withhold a working setting.
- **FR-008**: A module screen's availability MUST be derived from the `since_firmware` of
  that module's own field on `ModuleConfig`, replacing per-module version constants in
  screen code.
- **FR-009**: `excluded_modules` (from the device hardware catalog) and `since_firmware`
  answer different questions — "this board has no such module" versus "this firmware has
  no such field" — and neither substitutes for the other. Both MUST be consulted.

#### Controls

- **FR-010**: A control MUST be selected from the field's type and metadata by default:
  boolean to a toggle, enumeration to a picker over its values, an integer with bounds to
  a stepper, an integer with a time unit to an interval picker, a string to a text field.
- **FR-011**: A screen MAY override that choice from an enumerated set of control kinds:
  interval, GPIO pin, fixed option list, slider, stepper, segmented, secure entry,
  non-zero toggle, bit flags, precise decimal, IPv4 address, and an arbitrary custom view.
- **FR-012**: Custom controls MUST be counted per screen and pinned by a test, so adding
  one is a reviewed decision rather than a quiet default.
- **FR-013**: An enumeration picker MUST offer a row for the value the radio currently
  holds even when the app does not recognise it.
- **FR-014**: A picker MUST exclude deprecated values unless the radio currently holds
  one.

#### Layout

- **FR-015**: Sections, field order, and field-to-field visibility are owned by the
  client **(iOS only** in the sense that nothing upstream expresses them; see FR-024**)**.
- **FR-016**: The layout description MUST NOT carry any display text for a field — no
  label, description, unit or bound. If it could, the two sources would drift.
- **FR-017**: Visibility conditions that read another field's value MUST be typed against
  that field, so removing or renaming the field breaks the build rather than silently
  disabling the condition.
- **FR-018**: Conditions that read anything other than the message — hardware, firmware,
  connection state — MUST be counted per screen and pinned by a test, for the same reason
  as FR-012.

#### Loading and saving

- **FR-019**: A screen MUST load from the stored configuration entity and save through
  the existing configuration save path. This feature changes presentation, not transport.
- **FR-020**: A field that the entity does not persist MUST NOT be offered. It would load
  as the proto default regardless of the radio's value and write that default back.
- **FR-021**: Unsaved-change detection MUST be an exact comparison against the loaded
  value, so reverting an edit withdraws the save prompt.
- **FR-022**: Normalisation of loaded values MUST happen on the in-memory copy and MUST
  NOT mutate the stored entity.
- **FR-023**: A failed save MUST be surfaced to the operator, not only logged.

#### Gates the schema cannot express

- **FR-024**: Regulatory and hardware constraints MUST be expressed by the client, and
  MUST hide rather than guess when the relevant fact is unknown. Three shipped examples:
  duty cycle override offered only in regions with an hourly limit; PA fan offered only on
  the boards whose firmware drives one; Bluetooth wait offered only on the ESP32 family.
- **FR-025**: Where such a gate derives from data the app already holds, it MUST derive
  from it rather than restating it. The duty cycle gate reads the region's duty cycle
  percentage, so a change to that data carries.

### Key Entities

- **Field metadata** — the schema's per-field annotations: label, description, unit,
  bounds, keywords, deprecation, and the two firmware-window versions. Shared by every
  client. Scalar attributes only.
- **Field descriptor** — generated per message: the field's tag, name, type and a typed
  accessor. This is what lets a layout entry name a field in a way the compiler checks.
- **Layout overlay** — per screen: ordered sections, each with an optional heading and
  footer, containing ordered field entries. Each entry names a field and may add a symbol,
  a control override and visibility conditions. Carries no display text for fields.
- **Form environment** — the facts a condition may read beyond the message: the node being
  configured, whether it is connected, whether it is the connected node, whether the
  board is a DIY build, whether it has WiFi or Ethernet, whether it supports the newer
  key exchange, and the firmware comparison itself.
- **Form runtime** — the view that walks a layout, renders each entry, tracks unsaved
  changes, validates, and drives the save.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 22 of the 24 radio configuration messages render from the schema; the two
  that do not are named with a reason.
- **SC-002**: Zero field labels, descriptions, units or bounds are written into a
  migrated screen.
- **SC-003**: Every field of every migrated message is accounted for — laid out or
  omitted with a reason — enforced by a test rather than by review.
- **SC-004**: Zero firmware version constants remain in migrated screen code for
  field-level gating.
- **SC-005**: A field that gains a description upstream shows helper text after a
  submodule bump and regeneration, with no screen edit.
- **SC-006**: Custom controls and environment conditions are pinned per screen, so their
  count cannot grow without a reviewed change.
- **SC-007**: A schema change that adds or renames a field fails the build or a test
  rather than silently producing a screen that no longer matches the protobufs.

## Clarifications

### Session 2026-09-20

- Q: Where do sections, order and field-to-field visibility live? → A: With the client.
  `FieldMetadata` has no attribute for any of them and none has been proposed upstream.
  Recorded as FR-024's sibling gap in **Out of Scope**.
- Q: Should the layout be data (JSON) or code? → A: Code. It must reference fields in a
  way that breaks the build when a field is removed, and it holds nothing translators or
  other clients would consume. A data format would give up the first without earning
  anything.
- Q: Can the form be built by reflecting over the protobuf message at runtime? → A: No.
  The Swift protobuf runtime does not enumerate fields that hold their default value, and
  generic writes need per-field type information the runtime does not expose. Descriptors
  must be generated at build time.
- Q: What happens to a screen with constraints no generic control covers? → A: It keeps
  the custom parts as hand-written sections and renders its ordinary fields from the
  schema. Fully bespoke is reserved for messages where that split does not help
  (`MeshBeaconConfig`).
- Q: Is a labelled field automatically safe to offer? → A: No. It must also be persisted
  by the configuration entity. #2530 found `pa_fan_disabled` labelled but unstored;
  offering it needed the entity property first. Adding a property to the stored model is
  an inferred migration and does not need a schema version.
- Q: Do deprecated fields get labels? → A: Yes, when `deprecated_since` is set. The
  attribute exists precisely so a client can keep offering the field on firmware that
  still reads it, and without a label it cannot.
- Q: Should search and the forms apply the firmware window the same way? → A: They should.
  Today the forms apply it and search does not. Recorded as a known divergence in spec 019
  rather than resolved here.

## Dependencies

- **`FieldMetadata` in meshtastic/protobufs** — the eleven scalar attributes. In
  particular `since_firmware` and `deprecated_since`, added in protobufs#1104, without
  which US1 cannot be satisfied.
- **The generated metadata registry** — spec 019. This feature is its second consumer and
  is now the larger one.
- **Generated field descriptors** — per-message tags, names, types and typed accessors,
  produced at build time from the same protos.
- **Annotation coverage upstream.** A screen can only migrate once its fields are
  labelled. Fields still unlabelled are listed as omitted, which is honest but is a gap,
  not a resting state.

## Assumptions

- Firmware defends itself. A client may write a field a newer firmware ignores, or omit
  one an older firmware wanted; the annotations are presentation metadata and are not a
  wire contract.
- The stored configuration entity remains the app's source of truth for a screen's
  starting values, and the radio's echo of a saved configuration remains what updates it.
- Section headings stay client-owned for now, and therefore stay translated per client.
- The set of control kinds is closed enough that new screens pick from it rather than
  extending it. Extending it is allowed but is a reviewed change.

## Out of Scope

- **Sections and field order upstream.** `section`, `order` and field-dependency
  attributes were considered and are not proposed. Until they exist, every client decides
  grouping and ordering independently and nothing detects when they disagree. This is the
  largest remaining duplication between clients and is recorded here so it is not
  mistaken for an oversight.
- **`MeshBeaconConfig`** — stays hand-written; a repeated-target editor and channel
  resolution.
- **`RtttlConfig`** — not a configuration message.
- **App-level settings** that have no protobuf field at all. They are indexed by settings
  search through a separate generated catalogue and are not part of this feature.
- **The remaining unlabelled fields.** Roughly twenty fields across the migrated messages
  carry no label upstream and so cannot be offered. Annotating them is upstream work.
- **Search honouring the firmware window.** A real divergence between this feature and
  spec 019, recorded there.
