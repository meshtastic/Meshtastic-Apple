# Feature Specification: Site Planner Outbound Coverage Estimate

**Feature Branch**: `015-site-planner-outbound`
**Created**: 2026-07-07
**Status**: Draft
**Input**: User description: "Outbound Site Planner coverage estimate for the iOS/macOS app — let a user kick off a Site Planner RF coverage run from the app and receive the styled coverage back as a map overlay, without leaving the app or using a browser/share sheet. Per Meshtastic-Apple#2058 and the cross-platform spec at meshtastic/design#119; mirrors the shipped reference implementation at Meshtastic-Android#6136."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Estimate coverage from a node's detail screen (Priority: P1)

A user viewing a node that has a known position wants to see that node's expected radio coverage without leaving the app or manually operating a separate web tool. They start a coverage estimate from the node's detail screen, review a short form of transmitter and radio parameters (prefilled from the node's position and the connected radio's current configuration where available), and submit. The coverage is computed and appears as a new colored overlay on the mesh map, named after the site — all inside the app.

**Why this priority**: This is the core value proposition of the feature — the single most common way a user would want to answer "how far will my node reach from here?" without context-switching to a browser.

**Independent Test**: Open a node with a known position, start the estimate action, submit with default values, and verify a new named overlay appears on the mesh map within a reasonable time, with no browser or share sheet involved at any point.

**Acceptance Scenarios**:

1. **Given** a node with a known position and a connected radio, **When** the user starts a coverage estimate from that node's detail screen and submits with default values, **Then** a new named coverage overlay appears on the mesh map without the user leaving the app.
2. **Given** the same flow, **When** the estimate is running, **Then** the user sees a clear in-progress state and cannot start a second overlapping estimate in the meantime.
3. **Given** a completed estimate, **When** its overlay is added to the map, **Then** it renders with the same fill/stroke styling behavior as an overlay imported from a GeoJSON file.

---

### User Story 2 - Estimate coverage from an arbitrary map location (Priority: P2)

A user looking at the mesh map — not necessarily at any existing node — wants to test "what if I put a node here?" at a location of their choosing (e.g. a candidate tower or hilltop), independent of any node already in their mesh.

**Why this priority**: Extends the same capability to speculative site planning. Valuable, but checking an existing node's coverage (User Story 1) is the more common need, hence P2.

**Independent Test**: From the map, start the estimate flow, confirm the prefilled location matches the current map view (or a chosen point), adjust parameters, submit, and verify the resulting overlay lands at the intended coordinates.

**Acceptance Scenarios**:

1. **Given** the mesh map is open, **When** the user starts a coverage estimate from the map (not from a node), **Then** the form is prefilled with a location derived from the current map view rather than requiring manual coordinate entry.
2. **Given** no radio is connected, **When** the user opens the estimate form this way, **Then** transmitter/receiver fields fall back to sensible defaults rather than blocking the flow.

---

### User Story 3 - Tune advanced parameters before running an estimate (Priority: P3)

A more advanced user wants to adjust simulation and display parameters (receiver sensitivity, max range, terrain resolution, color palette, signal-strength display range) rather than accepting defaults, to match a specific radio setup or produce a more legible overlay.

**Why this priority**: Valuable for power users and matches the scope already validated on the reference platform, but the feature delivers its core value even with only the basic site/transmitter fields — so this is the lowest-priority slice.

**Independent Test**: Open the estimate form, expand the advanced/simulation/display sections, change values away from their defaults, submit, and verify the resulting overlay reflects the changes (e.g. a different color palette or a visibly different coverage extent).

**Acceptance Scenarios**:

1. **Given** the estimate form is open, **When** the user changes the color palette, **Then** the resulting overlay uses that palette.
2. **Given** the estimate form is open, **When** the user changes max range or receiver sensitivity, **Then** the resulting overlay's extent reflects the change.

---

### Edge Cases

- What happens when an estimate takes an unusually long time or never completes (poor network, an extreme simulation radius)? The user needs a way to see it's still working, and to cancel.
- What happens when the user tries to submit a second estimate before the first finishes?
- What happens when the remote coverage computation fails or returns no usable result?
- What happens when the device has no network connectivity at all?
- What happens when a node has no known position and the user tries to estimate from its detail screen?
- What happens when a new estimate's site name collides with an existing overlay's name?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Users MUST be able to start a coverage estimate from a node's detail screen when that node has a known position.
- **FR-002**: Users MUST be able to start a coverage estimate from the mesh map at a location of their choosing, independent of any specific node.
- **FR-003**: The estimate form MUST be prefilled with the connected radio's current transmit frequency, transmit power, and receiver sensitivity where that information is available, and MUST fall back to reasonable defaults when it is not (no connected radio, or a value the firmware doesn't expose).
- **FR-004**: Users MUST be able to review and adjust site/transmitter, receiver, simulation, and display parameters before submitting an estimate, mirroring the parameter set and grouping already established by the reference web tool and the shipped Android implementation.
- **FR-005**: The system MUST perform the coverage computation without requiring the user to leave the app, open a separate browser, or manually handle a downloaded/shared file.
- **FR-006**: On successful completion, the system MUST add the resulting coverage as a new, named, styled overlay on the mesh map, using the same rendering/styling behavior as overlays imported from a GeoJSON file.
- **FR-007**: The system MUST show the user a clear in-progress state while an estimate is running, and MUST prevent starting a second concurrent estimate until the first resolves or is canceled.
- **FR-008**: Users MUST be able to cancel an in-progress estimate.
- **FR-009**: The system MUST surface a clear, actionable error to the user when an estimate fails or times out, rather than failing silently.
- **FR-010**: The feature MUST behave equivalently on every supported platform variant of the app (iPhone, iPad, and Mac).
- **FR-011**: This feature MUST NOT require or duplicate the separate, already in-progress capability for importing a GeoJSON file into the app — that remains a distinct entry point and is out of scope here.

### Key Entities *(include if feature involves data)*

- **Coverage Estimate Request**: The set of site/transmitter/receiver/simulation/display parameters a user has configured for a single run — including position and radio characteristics. Not persisted beyond the session unless the user keeps the resulting overlay.
- **Coverage Overlay**: The named, styled result of a completed estimate, rendered on the mesh map. Shares its representation with overlays produced by the existing GeoJSON-import feature — from the user's perspective, an estimate is just another way to add one.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from "viewing a node" to "seeing that node's coverage overlay on the map" in under 4 steps and without leaving the app.
- **SC-002**: At least 90% of estimate submissions with default/prefilled values complete and render successfully on a typical network connection.
- **SC-003**: An estimate-produced overlay is visually indistinguishable from a manually-imported one unless the user deliberately inspects its source.
- **SC-004**: The feature is usable, with equivalent steps and outcomes, on phone, tablet, and desktop form factors.

## Assumptions

- The remote coverage computation has no server-side API and can only be produced inside a real browser/web-engine context; this feature works by driving that web engine invisibly inside the app rather than by calling a backend service directly. (Confirmed via the reference platform's own documentation and the shipped Android implementation.)
- v1 scope mirrors the Android reference implementation's parameter coverage (site/transmitter, receiver, simulation options, display) rather than a reduced subset, since that scope is already validated cross-platform and consistency between platforms is valuable.
- Entry points mirror Android exactly: a map-toolbar control (location-agnostic) and a node-detail action (position-specific, shown only when the node has a position).
- When no radio is connected, or the firmware doesn't expose a needed value, the form falls back to the same factory defaults the reference web tool itself uses.
- Overlay naming/styling reuses the app's existing GeoJSON overlay pipeline unchanged; an estimate result is not a visually distinct category of overlay.
- Importing a `.geojson` file directly (the separate, already in-progress capability) is explicitly out of scope for this feature and is not affected by it.
- The exact low-level mechanism for retrieving the result from the embedded web engine (message-passing contract, timeout values, retry behavior) is a technical/planning-level decision, not a product-scope one, and will be finalized during planning against the reference platform's actual source rather than assumed here.
- Mac (desktop) support is a first-class requirement, not a stretch goal, consistent with the rest of the app's platform support.
