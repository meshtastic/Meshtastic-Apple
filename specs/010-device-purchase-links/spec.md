# Feature Specification: Device msh.to Links

**Feature Branch**: `010-device-purchase-links`  
**Created**: 2026-05-15  
**Status**: Draft  
**Input**: User description: "Import the msh.to urls.json file during device hardware data import and populate links on vendor and product data so we can use the links in the code to point users to additional documentation and links for supported devices from our backers and partners."

## Clarifications

### Session 2026-05-15

- Q: How should retailer-specific links (e.g., rokland-rak4631) be associated with devices when only the base slug matches? → A: Substring/prefix matching — associate links whose shortCode contains the device's hwModelSlug.
- Q: How should the app access the urls.json at runtime (repo is private)? → A: Bundled-only for v1, updated via CI/build script. Future version may fetch from public URL.
- Q: How should vendor+locale priority ordering work? → A: Static vendor priority list (manufacturer direct > regional retailer by locale > global marketplace), vendor extracted from URL domain.
- Q: Where in the UI should device-specific links appear? → A: As a "Links" section within the existing node info/hardware detail view, tappable rows with description and Safari icon.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View msh.to Links for Connected Device (Priority: P1)

A user connects to a Meshtastic device and wants to find relevant links for that hardware — vendor pages, documentation, retailer listings. They navigate to the device info view and see msh.to links associated with that device.

**Why this priority**: The primary value of this feature is connecting users to relevant resources for hardware they already own or are viewing in the app, directly supporting Meshtastic's backer and partner ecosystem.

**Independent Test**: Connect to any supported device, open its hardware info view, and verify that one or more msh.to links are displayed with correct URLs.

**Acceptance Scenarios**:

1. **Given** a user is viewing node info for a RAK WisMesh Pocket, **When** they view the hardware details, **Then** they see msh.to links to RAK Store, Rokland, Hexaspot, and AliExpress with correct URLs.
2. **Given** a user is viewing node info for a Heltec V3, **When** they view the hardware details, **Then** they see msh.to links to Heltec, Rokland, and AliExpress.
3. **Given** a user is viewing a device with no matching links in the database, **When** they view the hardware details, **Then** no links section is shown (graceful absence, not an error).

---

### User Story 2 - Links Stay Current via Background Refresh (Priority: P2)

The link data stays up to date as vendors add new products or update URLs. The app fetches the latest links from the meshtastic/msh.to repository during the existing device hardware refresh cycle, falling back to a bundled snapshot when offline.

**Why this priority**: Stale links lead to 404s and frustrated users. Keeping data fresh ensures the feature remains useful over time without manual app updates.

**Independent Test**: Modify a URL in the remote source, trigger a device hardware refresh, and verify the updated URL appears in the app.

**Acceptance Scenarios**:

1. **Given** the bundled links file is updated in a new app release, **When** the device hardware data refreshes, **Then** the new links are loaded and stored locally.
2. **Given** a link URL changes in a future bundled update, **When** the app is updated, **Then** the stored link is updated to the new URL.

---

### User Story 3 - Browse All msh.to Links (Priority: P3)

A user browsing for new hardware wants to explore all available Meshtastic devices and accessories from partner vendors, even those not currently connected. A section in Settings provides a categorized directory of all available msh.to links.

**Why this priority**: Supports discovery and the partner/backer ecosystem, but is secondary to the device-specific links that appear contextually.

**Independent Test**: Open the link directory view and verify all imported msh.to links are displayed, grouped by vendor or device type, with working URLs that open in the system browser.

**Acceptance Scenarios**:

1. **Given** a user opens the link directory, **When** links are loaded, **Then** all imported msh.to links are displayed grouped by vendor (RAKwireless, Heltec, LilyGo, Seeed, Elecrow, etc.).
2. **Given** a user taps a link, **When** the link is activated, **Then** the URL opens in the system browser (Safari).

---

### Edge Cases

- What happens when the remote urls.json is malformed or has an unexpected schema change?
- How does the system handle duplicate short codes in the source data?
- What happens if the msh.to repository becomes unavailable or is renamed?
- How are non-device links (discord, youtube, docs, android, etc.) handled — stored but not associated with hardware?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST import link data from a bundled copy of the meshtastic/msh.to `urls.json` during the device hardware refresh cycle. The bundled copy is updated via CI/build script before each release.
- **FR-002**: System MUST associate links with device hardware entities using substring/prefix matching — links whose short code contains the device's hardware model slug are associated with that device (e.g., `rokland-rak4631`, `hexaspot-4631`, `aliexpress-rak4631` all associate with the `rak4631` device).
- **FR-003**: System MUST store each link's short code, destination URL, and description.
- **FR-004**: System MUST use the bundled links file (no runtime network fetch in v1; future enhancement may add a public CDN fetch with bundled fallback).
- **FR-005**: System MUST update stored links when newer data is fetched from the remote source.
- **FR-006**: System MUST support multiple links per device (different vendors/retailers for the same hardware).
- **FR-007**: System MUST retain links that don't match any device (general Meshtastic resources, vendor homepages) for use in a browsable directory.
- **FR-008**: System MUST open link URLs in the system browser when activated by the user.
- **FR-008a**: Device-specific links MUST appear as a "Links" section within the existing node info/hardware detail view, displayed as tappable rows with the link description and a Safari external-link icon. No new screen is required for P1.
- **FR-009**: System MUST order device links by a static vendor priority: manufacturer direct store first (e.g., rakwireless.com, heltec.org, lilygo.cc), then regional retailers preferred for the user's locale (e.g., Rokland for US, Hexaspot for EU), then global marketplaces (AliExpress, Amazon). Vendor is extracted from the link URL domain.

### Key Entities

- **DeviceLink**: Represents a single URL entry from msh.to — has a short code (identifier), destination URL, human-readable description, and optional association to a device hardware record.
- **DeviceHardware** (existing): Extended with a collection of associated DeviceLinks matched by hardware model slug.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can find msh.to links for any actively-supported device within 2 taps from the node info view.
- **SC-002**: 100% of links from the msh.to source file are imported and accessible in the app.
- **SC-003**: Link data refreshes automatically without user intervention whenever device hardware data refreshes.
- **SC-004**: The app functions correctly with the bundled fallback when offline — no crashes or empty states due to missing link data.

## Assumptions

- The meshtastic/msh.to repository will remain the canonical source for device and documentation links.
- The `urls.json` schema (Routes array with ShortCode, OriginalUrl, Description fields) will remain stable.
- Short codes in urls.json that match `hwModelSlug` values from the device hardware API represent links for those specific devices.
- Non-device links (social media, docs, apps) are valuable for a browsable directory but are lower priority than device-specific links.
- The bundled links file is updated via CI or build script before each release (no runtime network fetch in v1).
- A future version may add runtime fetching from a public URL (e.g., GitHub Pages) once the msh.to repo is made public or a CDN is configured.
