# Feature Specification: First-Launch Setup and Radio Setup

**Feature Branch**: `021-onboarding-radio-setup`

**Created**: 2026-11-07

**Status**: Implemented; this spec records what shipped

**Input**: A new user should learn what Meshtastic is before the app asks for permissions,
and a radio connected for the first time should be walked through the settings it needs to
talk to anyone: region, preset and name, and on firmware 2.8 a status message and the
meshes nearby.

## Audience

Written for maintainers of this repository and for the other Meshtastic client teams.
Rules any client has to apply, such as which presets a region allows or when a LoRa change
restarts the radio, are stated as such. Anything specific to this app is marked
**(iOS only)**, so another client knows where it is free to differ.

## Overview

Before this work, the first launch went straight into five permission pages that never
said what Meshtastic is, and a newly connected radio with no region got a red "Set LoRa
Region" link on the Connect screen and nothing else. A radio with no region cannot
transmit, so a new user could pair a radio, see it connected, and hear nothing.

The app now has two flows that share one page style:

| flow | when it opens | what it covers |
|---|---|---|
| First-launch setup | the first launch of the app | welcome, then Bluetooth, local network, notifications, location and Siri permissions |
| Radio setup | on its own once per radio with no region, or from a Set Up Radio row | region, preset, name; on 2.8 also status and nearby meshes |

The first-launch setup is about the phone. The radio setup is about the radio, and only
ever writes to the connected radio.

## Progress

| change | PR |
|---|---|
| Welcome page; permission pages restyled into a shared page layout | #2870 |
| Preset rules per region moved where the setup can reach them | #2871 |
| Radio setup flow, its automatic trigger and the Set Up Radio rows | #2873 |
| Radio setup and the 3D model open on the Vision Pro cinema's screen | #2881 |
| Status message and Nearby Meshes page on firmware 2.8 | #2906 |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A new radio gets on the mesh (Priority: P1)

Someone connects a radio fresh from the box. The app opens the radio setup by itself,
starts on the region their phone is set to, picks a legal preset for it, and lets them name
the radio. When they tap Done, the radio is transmitting on legal frequencies.

**Why this priority**: A radio with no region does not transmit. Nothing else in the app
works until this is done, and the old red link was easy to miss.

**Independent Test**: Connect a factory-reset radio. The setup opens once the radio has
sent its config. Finish it and check the radio's region, preset and name.

**Acceptance Scenarios**:

1. **Given** a connected radio whose region is unset and that the app has not offered
   setup for, **When** the radio finishes sending its config, **Then** the radio setup
   opens.
2. **Given** a phone set to a country with a clear answer (for example, the United
   States), **When** the region page opens, **Then** that region is selected, the title
   reads "Confirm Your Region" and the text says it came from the phone's region setting.
3. **Given** a phone set to a country with no clear answer, **When** the region page
   opens, **Then** nothing is selected and Continue stays disabled until a region is
   chosen.
4. **Given** a factory-fresh radio on firmware 2.8 or later and the US region, **When**
   the region is chosen, **Then** the preset moves from Long Fast to Long Turbo.
5. **Given** the preset page with a changed region or preset, **When** the user taps Save
   and Continue, **Then** the app makes one LoRa config save.

---

### User Story 2 - Only legal choices are offered (Priority: P1)

The region and preset pickers only offer what the connected firmware supports and what the
region allows. Where the radio reports a map of legal presets per region, the preset list
follows it.

**Why this priority**: Transmitting outside a region's rules is the one mistake the setup
must not make easy.

**Independent Test**: Connect a 2.8 radio and an older one. Compare the region lists and
the preset lists for EU 868 and US.

**Acceptance Scenarios**:

1. **Given** firmware older than 2.8, **When** the region picker opens, **Then** regions
   that need 2.8 are absent.
2. **Given** a 2.8 radio that sent its region preset map, **When** the preset page opens,
   **Then** only presets the map lists for the chosen region are offered, and the
   region's default is shown as "Recommended for <region>: <preset>".
3. **Given** a current preset the chosen region does not allow, **When** the region
   changes, **Then** the preset falls back to the region's default.
4. **Given** the US region on 2.8 and a preset that is not a Turbo preset, **When** the
   preset page shows, **Then** it warns that the preset's bandwidth is not compliant in
   the US.
5. **Given** a region the map marks licensed-only, **When** it is chosen, **Then** the
   licensed band notice shows, telling an unlicensed user to set Licensed Operator and a
   call sign first.
6. **Given** a region with an hourly duty cycle under 100%, **When** it is chosen,
   **Then** the page footer states the duty cycle.

---

### User Story 3 - The setup survives a restart (Priority: P2)

On firmware older than 2.8 a LoRa change restarts the radio. The setup says so before the
save, keeps its place while the radio reconnects, and saves the name once it is back.

**Why this priority**: A flow that falls apart on the restart it caused would leave the
radio half set up.

**Independent Test**: Run the setup on a 2.7 radio. Save a preset, watch the radio
restart, and save a name after it reconnects.

**Acceptance Scenarios**:

1. **Given** firmware that restarts for a LoRa change and a pending LoRa change, **When**
   the preset page shows, **Then** the footer says the radio restarts and reconnects in
   a few seconds.
2. **Given** the LoRa save just restarted the radio, **When** the name page shows,
   **Then** it says it is waiting for the radio to reconnect and Save stays disabled.
3. **Given** the radio reconnects, **When** it finishes sending its config, **Then** the
   name page can save.
4. **Given** firmware 2.8 or later, **When** the LoRa save succeeds, **Then** the radio
   does not restart and the app asks the radio for its node database again.

---

### User Story 4 - A new user knows what they are setting up (Priority: P2)

On first launch the app says what Meshtastic is, how it treats privacy, and that the next
pages set up features, before it asks for any permission.

**Why this priority**: Permission prompts with no context get declined.

**Independent Test**: Delete and reinstall the app. The welcome page shows before any
permission page.

**Acceptance Scenarios**:

1. **Given** the first launch, **When** the app opens, **Then** the welcome page shows
   with off-grid messaging, privacy and a note that the next pages set up the features
   the user wants.
2. **Given** the welcome page, **When** the user taps Get started, **Then** the pages
   follow in order: Bluetooth, local network, notifications, location, Siri.
3. **Given** the phone already allows location use, **When** the notifications page is
   done, **Then** the location page is skipped.

---

### User Story 5 - Coming back to the setup later (Priority: P3)

Someone who chose Not Now, or wants to change their radio's settings, reopens the setup
from Connect or Settings.

**Acceptance Scenarios**:

1. **Given** a connected radio with no region, **When** the Connect screen shows, **Then**
   a large red Set Up Radio row with "Region not set" is there.
2. **Given** a connected radio with a region, **When** the Connect screen shows, **Then**
   a small Set Up Radio row is there.
3. **Given** Settings with the connected radio selected, **When** Radio Configuration
   shows, **Then** Set Up Radio is its first row. It is absent while a remote node is
   selected.
4. **Given** the setup closed with Not Now, **When** the same radio reconnects later,
   **Then** the setup does not open by itself again.

---

### User Story 6 - A 2.8 radio finds the meshes around it (Priority: P3)

On firmware 2.8 a radio can set a status message and listen for beacons that nearby meshes
broadcast. The setup offers both, so a new user can find a local mesh without knowing
where Local Mesh Discovery is.

**Why this priority**: A radio set up on the default channel may hear nobody. A mesh
nearby that advertises itself is the quickest way onto one.

**Independent Test**: Run the setup on a 2.8 radio and on an older one. Only the 2.8
radio shows the status row and the Nearby Meshes page.

**Acceptance Scenarios**:

1. **Given** a 2.8 radio, **When** the name page shows, **Then** the names box has a third
   row, Status, starting with the radio's current status.
2. **Given** a status typed on the name page, **When** the user taps Save and Continue,
   **Then** the status is saved with the names and shows in the node list at once.
3. **Given** a 2.8 radio, **When** the name page is done, or the preset page for a
   licensed operator, **Then** the Nearby Meshes page shows before the done page.
4. **Given** the Nearby Meshes page, **When** the user turns on Listen for Beacons,
   **Then** only the listen flag of the radio's beacon config changes.
5. **Given** beacons heard outside a scan, **When** the page shows, **Then** up to five are
   listed, newest first, with Join, and with Add when the mesh runs on the radio's own
   preset and frequency slot.
6. **Given** the Nearby Meshes page, **When** the user taps Scan for Meshes or Broadcast a
   Beacon, **Then** Local Mesh Discovery or the Mesh Beacon settings open inside the setup,
   and Back returns to it.
7. **Given** firmware older than 2.8, **When** the setup runs, **Then** neither the status
   row nor the Nearby Meshes page shows.

### Edge Cases

- **Config not received yet**: the automatic trigger waits until the radio's region is
  known and the connection is subscribed. An unknown region is not treated as unset.
- **Other gates up**: the setup does not open by itself while the first-launch setup, the
  lockdown gate, the firmware update gate or a database reset is showing. The rows also
  do nothing while those gates are up.
- **A different radio connects mid-flow**: the setup closes. Its settings belong to the
  other radio.
- **Disconnected at save time**: the save fails with "Your radio is not connected.
  Reconnect and try again." and the page stays.
- **Custom modem settings**: a radio not on a preset keeps its bandwidth, spread factor and
  coding rate through a region change. The preset page says so, and only choosing a preset
  there puts it back on a preset.
- **Radio reports a region this app does not know**: the region page shows the
  unsupported region notice, and Continue stays disabled until a known region is picked.
- **Licensed operator**: the name page is skipped, because a licensed operator's long name
  comes from the call sign. The intro and done pages leave out the name row.
- **Nothing changed**: Continue on the preset and name pages makes no save.
- **Name limits**: the short name is cut to 4 bytes; the long name to the radio's limit,
  which depends on firmware. Emoji variation selectors are removed. Names already on the
  radio are not cut until the user edits them.
- **Node missing from the store**: after a reset emptied the store, the setup shows "Radio
  Not Found".
- **Beacon config not received yet**: Listen for Beacons stays disabled and says it is
  waiting. The page asks the radio for its beacon config.
- **Listening but nothing heard**: the page says so. A beacon interval is at least an
  hour, so a mesh can take that long to show up.
- **Licensed operator on 2.8**: the name page, and with it the status row, is skipped. The
  Nearby Meshes page still shows.

## Requirements *(mandatory)*

### Functional Requirements

**Triggering**

- **FR-001**: The radio setup MUST open by itself when all of these are true: a radio is
  connected and subscribed, its region is known and is `UNSET`, the app has not opened
  the setup by itself for that node number before, and no other gate (first-launch setup,
  lockdown, firmware update, database reset) is showing.
- **FR-002**: The app MUST record the node number as offered before the setup opens, so a
  radio the user closes the setup on, or that disconnects mid-flow, is never offered again
  automatically. **(iOS only: stored in `UserDefaults.radioSetupOfferedNodeNums`.)**
- **FR-003**: The setup MUST be reachable at any time from a Set Up Radio row on the
  Connect screen and at the top of Settings → Radio Configuration, while connected.
- **FR-004**: The setup MUST only write to the connected radio. It MUST NOT be offered
  while a remote node is selected for administration.

**Region**

- **FR-005**: When the radio's region is `UNSET`, the region page MUST start on the region
  suggested by the phone's region setting, when the country maps to one region. It MUST
  say the region came from the phone and ask for a confirmation.
- **FR-006**: A radio that already has a region MUST start on that region, with no
  suggestion.
- **FR-007**: The region list MUST leave out regions hidden from pickers and, below
  firmware 2.8, regions that need 2.8.
- **FR-008**: Continue MUST stay disabled until a region the app can write is selected.
- **FR-009**: The region page MUST show the licensed band notice for a region the radio
  marks licensed-only, and the hourly duty cycle for a region limited to under 100%.

**Preset**

- **FR-010**: On firmware 2.8 or later, choosing a region MUST apply these rules in order:
  1. A factory-fresh radio choosing US on Long Fast, or on no preset, moves to Long Turbo
     when the region allows it.
  2. A current preset the region allows stays.
  3. Otherwise the preset becomes the region's default from the radio's map.

  Below 2.8, or on custom modem settings, the preset does not change.
- **FR-011**: A factory-fresh radio MUST be put on a preset when a region is chosen. A
  configured radio MUST keep its mode, so custom modem settings survive a region change.
- **FR-012**: The preset list MUST follow the radio's region preset map when it sent one.
  A map that names none of the presets this app offers counts as no map.
- **FR-013**: On 2.8 and the US region, a preset that is not a Turbo preset MUST show the
  bandwidth warning.
- **FR-014**: The preset page MUST make at most one LoRa config save, and only when the
  region, preset or preset mode changed.
- **FR-015**: Below 2.8, the preset page MUST warn before the save that the radio
  restarts. On 2.8 the change applies live, and the app MUST ask for the node database
  again after the save.

**Name**

- **FR-016**: The name page MUST be skipped for licensed operators.
- **FR-017**: The short name MUST be limited to 4 bytes and the long name to the radio's
  limit. Both MUST be limited as typed, not by cutting stored names.
- **FR-018**: Save MUST stay disabled while the long name is blank, the short name is
  empty, or the radio is reconnecting after a LoRa save.
- **FR-019**: The name save MUST keep the radio's unmessagable flag.
- **FR-020**: The name page MUST preview the node's circle in the same color the node
  lists use, following the short name as it is typed. **(iOS only.)**

**Flow**

- **FR-021**: The pages MUST follow intro → region → preset → name → done, with the name
  page left out for licensed operators. On firmware 2.8 the Nearby Meshes page comes
  before done.
- **FR-022**: The intro MUST offer Not Now, which closes the setup with nothing saved.
  The name page MUST offer Skip.
- **FR-023**: The done page MUST read back the region, preset (or "Custom") and name, and
  on 2.8 the status and whether the radio listens for beacons.
- **FR-024**: The flow MUST keep its own copy of what it shows, so a restart or reconnect
  mid-flow leaves it standing. Saves MUST look up the connected radio's user at save time.
  **(iOS only: the model holds no SwiftData objects.)**
- **FR-025**: A save error MUST show on the page, and the page MUST stay.
- **FR-026**: If a different radio becomes the connected one, the setup MUST close.

**First-launch setup**

- **FR-027**: The first launch MUST show a welcome page before any permission page.
- **FR-028**: The permission pages MUST follow in order: Bluetooth, local network,
  notifications, location, Siri. The location page MUST be skipped when location use is
  already allowed.
- **FR-029**: The first-launch setup MUST NOT be dismissible by swiping down, and on
  closing it MUST start looking for radios.

**Presentation (iOS only)**

- **FR-030**: Both flows MUST use the shared `OnboardingPage` layout: title, intro, rows,
  footer, one pinned primary button and an optional secondary button. Rows MUST stack at
  accessibility text sizes so nothing is cut off.
- **FR-031**: The primary button MUST ignore a second tap while its action runs.
- **FR-032**: On Apple Vision Pro's cinema screen, where sheets never show, the radio
  setup MUST cover the current section and close through a callback.

**Status and nearby meshes (firmware 2.8)**

- **FR-033**: On 2.8 the name page MUST include a Status field, starting with the radio's
  configured status, or its broadcast one when none is configured. It MUST be limited to
  80 bytes as typed.
- **FR-034**: The status MUST be saved with the names, only when it changed, through the
  Status Message module config.
- **FR-035**: Listen for Beacons MUST write the radio's stored beacon config back with only
  the listen flag changed. It MUST stay disabled until the radio has sent its beacon config.
- **FR-036**: The page MUST list beacons heard outside a scan, newest first, at most five,
  with the same Join and Add actions and confirmations as Local Mesh Discovery.
- **FR-037**: The page MUST link to Local Mesh Discovery and to the Mesh Beacon settings.
- **FR-038**: Below 2.8 the status field and the Nearby Meshes page MUST NOT show.

### Key Entities

- **RadioSetupModel**: the setup's state. Plain values copied from the node (names,
  hardware, firmware, LoRa config), the draft LoRa config and names, the suggested region,
  the page path, and the save and reconnect state.
- **RadioSetupTrigger**: the inputs and the decision for the automatic open (FR-001).
- **RegionCodes.suggested(forCountryCode:)**: a country-to-region table. It returns nil
  where there is no clear answer.
- **ModemPresets.presetToSelect**: the preset rules in FR-010.
- **MeshBeaconConfigValues(entity:)**: the stored beacon config as values, so one setting
  can change and the rest go back as they were (FR-035).
- **BeaconJoinController**: the Join, Add and Replace actions and their confirmations,
  shared with Local Mesh Discovery.
- **AccessoryManager.connectedLoRaRegionCode**: the connected radio's region. It is set
  from its config and from the app's own LoRa saves, and cleared on disconnect.

## Success Criteria *(mandatory)*

- **SC-001**: A factory-fresh radio can be set up end to end, from connect to Done,
  without opening Settings.
- **SC-002**: No path through the setup can save a region and preset combination the
  radio's region preset map does not allow.
- **SC-003**: The setup opens by itself at most once per radio.
- **SC-004**: All pages render at accessibility text sizes with nothing truncated.

## Testing

- `RadioSetupModel`: page order including the licensed skip, region and preset choices on
  2.8 and older firmware, the restart warning following the firmware gate, name trimming,
  the save gates, the summaries, the Nearby Meshes page only on 2.8, and the status limit.
- `MeshBeaconConfigValues(entity:)`: a listen change keeps the offer, message, slot,
  interval and targets.
- `RadioSetupTrigger`: opens once for an unset region, and not before the config arrives,
  before the subscription, or while any gate is up.
- `LoRa presets by region`: the preset list with and without the region map, on old and
  new firmware, for EU, US and an unknown region.
- `SetupGuide`: every first-launch transition, including the location skip.
- Snapshots of every page in both flows, used by the docs.

## Assumptions

- The phone's region setting is a reasonable first guess for where the radio is. It is
  only a starting point, and the user confirms it.
- The country table covers the common cases. Countries with more than one plausible
  region, or none, are left for the user to pick.

## Out of Scope

- Channel setup, and joining a mesh from a QR code. Joining from a beacon is covered
  only for beacons already heard (FR-036); scanning stays in Local Mesh Discovery.
- Setting up a remote node.
- Moving the first-launch permission pages to after a radio is connected.

## Open Questions for Other Clients

- Should the automatic setup open once per radio, as here, or every time a radio with no
  region connects?
- Should the region suggestion come from the phone's region setting, as here, or from its
  location?
- Should the setup turn on listening for beacons by default on 2.8, rather than leaving
  it to the user?
- Should every client use the same country-to-region table? It is not in the protobufs or
  the firmware today.
