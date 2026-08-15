# Feature Specification: Need Hardware Carousel

**Feature Branch**: `chore/about-page-image`
**Created**: 2026-08-14
**Status**: Implemented on iOS (PR #2285); this spec exists so Android and other clients can build the same feature
**Input**: User description: "Update the About page store row to match the Need Hardware? section on meshtastic.org: link to the hardware anchor, use the site's description text, rotate through images of the featured devices, and show it in every region."

## Overview

meshtastic.org has a "Need Hardware?" section (the modal behind the button on the home page, anchored at `https://meshtastic.org/#hardware`) that tells new users Meshtastic needs a compatible radio and shows the most popular ready-to-use devices from backers and partners. The app's About screen mirrors that section as a single row: a "Need Hardware?" link, the site's description text, and an image carousel that cycles through the featured devices using the device images the app already ships for its hardware catalog.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Discover where to buy hardware from the About screen (Priority: P1)

A user without a radio (or shopping for another) opens the app's About screen. The first row of the apps section shows a rotating picture of a popular device, a "Need Hardware?" heading that is a link, and a short description. Tapping the link opens `https://meshtastic.org/#hardware` in the browser, where the site presents the full featured-device list and vendor links.

**Why this priority**: The app is useless without a radio; pointing new users at official partner hardware is the single most valuable thing the About screen does. Everything else in this feature decorates this row.

**Independent Test**: Open About, verify the row renders with an image, the heading, and the description, and that tapping the heading opens the hardware section of meshtastic.org in the system browser.

**Acceptance Scenarios**:

1. **Given** the About screen is open, **When** the apps section renders, **Then** it contains a row with a device image on the leading side and, beside it, a "Need Hardware?" link followed by the description text.
2. **Given** the row is visible, **When** the user taps "Need Hardware?", **Then** the device browser opens `https://meshtastic.org/#hardware`.
3. **Given** the device locale/region is anything at all, **When** About renders, **Then** the row is present (no region gating).

---

### User Story 2 - See the featured devices rotate (Priority: P2)

While the row is on screen, the device image cycles through the seven devices featured in the site's Need Hardware? section, cross-fading from one to the next every few seconds, looping forever.

**Why this priority**: The rotation is what makes the row feel alive and shows the breadth of the hardware ecosystem, but a static image still satisfies story 1.

**Independent Test**: Leave About open for ~25 seconds and verify the image changes roughly every 3 seconds, fades rather than snaps, and wraps back to the first device after the last.

**Acceptance Scenarios**:

1. **Given** the row is visible, **When** 3 seconds elapse, **Then** the image cross-fades to the next device in the list.
2. **Given** the last device in the list is showing, **When** the next tick fires, **Then** the first device shows again (wrap-around).
3. **Given** the user scrolls away and back, **Then** the carousel keeps cycling; no interaction is required and the carousel itself is not a tap target distinct from the row.

---

### Edge Cases

- One or more device images fail to load (missing from the bundle/catalog): skip them and cycle through whatever loaded. If only one image loads, show it statically. If none load, show an empty space of the reserved size — the link and description must remain usable.
- Accessibility: the image is decorative; the link and description carry the row's meaning. Reduced-motion settings may disable the cross-fade animation (plain swap is acceptable).
- The carousel must not tick when the About screen is not on screen in a way that leaks timers (platform-idiomatic lifecycle handling).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The About screen MUST show a hardware row containing a device image, a "Need Hardware?" link, and the description text, in every region and locale.
- **FR-002**: The link MUST open `https://meshtastic.org/#hardware` in the system browser.
- **FR-003**: The description text MUST read exactly: "Meshtastic requires a compatible device. Our backers and partners offer ready-to-use hardware. Here are some of the most popular options." (localizable through the normal string pipeline).
- **FR-004**: The image MUST cycle through the featured devices in FR-005 order, advancing every 3 seconds with a ~0.5 second cross-fade, wrapping after the last.
- **FR-005**: The device list MUST match the site's Need Hardware? section. As of 2026-08-14 that is, in order, with the shared device-catalog image names:

  | # | Device | Maker | Catalog image |
  |---|--------|-------|---------------|
  | 1 | T-Deck Plus | LILYGO | `t-deck.svg` |
  | 2 | R1 Neo | muzi works | `muzi_r1_neo.svg` |
  | 3 | T1000-E Tracker | Seeed Studio | `tracker-t1000-e.svg` |
  | 4 | Station G2 | B&Q Consulting | `station-g2.svg` |
  | 5 | WisMesh Tag | RAK Wireless | `rak_wismesh_tag.svg` |
  | 6 | Mesh Pocket | Heltec | `heltec_mesh_pocket.svg` |
  | 7 | ThinkNode M1 | Elecrow | `thinknode_m1.svg` |

- **FR-006**: Images MUST come from the client's existing device-hardware image catalog (the same images shown on node hardware pages), not from new bespoke artwork, and MUST be shipped with the app so the row works offline.
- **FR-007**: Images that fail to load MUST be skipped without breaking the rotation, per Edge Cases.
- **FR-008**: The image MUST render at a size that dominates the row's leading edge (iOS uses a 110×130 pt fit box; match the visual weight, not the exact points).

### Key Entities

- **Featured device**: a (display name, maker, catalog image name) triple. The list is a hard-coded client-side constant mirroring the site; it is not fetched at runtime.
- **Device-hardware image catalog**: the existing per-device SVG artwork every client already uses for hardware pages (same file names across platforms).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user on the About screen can reach the meshtastic.org hardware section in one tap.
- **SC-002**: All seven featured devices are seen within 21 seconds of the row being on screen.
- **SC-003**: The row renders identically (content-wise) regardless of device region, locale, or network availability.

## Assumptions

- The site's featured-device list changes rarely; updating the hard-coded list (and this spec's table) when it does is an acceptable maintenance cost. No runtime dependency on meshtastic.org is wanted for rendering the row.
- Every client bundles or can bundle the seven catalog SVGs. On iOS the images folder is bundle-size-trimmed via an exclude list, so exactly these seven were added to the app bundle (~120 KB total); Android should verify its equivalent packaging includes them.
- The description string ships in English and flows through each client's normal localization pipeline.

## iOS Reference Implementation

PR: meshtastic/Meshtastic-Apple#2285. All UI lives in `Meshtastic/Views/Settings/About.swift`:

- `RotatingHardwareImage` — a private SwiftUI view holding the seven image names, parsing the bundled SVGs once with SwiftDraw on appear, then advancing an index on a 3-second timer inside `withAnimation(.easeInOut(duration: 0.5))`; the image view is keyed by index with an opacity transition, which produces the cross-fade.
- The row is an `HStack`: `RotatingHardwareImage()` in a 110×130 pt frame, then a `VStack` with `Link("Need Hardware?", …/#hardware)` and the description `Text` in a callout font.
- The SVGs load from the app bundle root (`Bundle.main.url(forResource:withExtension:nil)`) — the iOS build copies the images folder flat. `project.yml` un-excludes exactly the seven files from the bundle-size trim.
