14266# Feature Specification: Device msh.to Links

**Feature Branch**: `010-device-mshto-links`  
**Created**: 2026-05-15  
**Status**: Implemented  
**Input**: User description: "Import the msh.to urls.json file during device hardware data import and populate links on vendor and product data so we can use the links in the code to point users to additional documentation and links for supported devices from our backers and partners."

## Clarifications

### Session 2026-05-15

- Q: How should links be associated with devices? → A: Multi-tier matching on `platformioTarget`:
  1. **Vendor links**: Exact match (`shortCode == platformioTarget`) — shown prominently with `.body` font and `.semibold` weight.
  2. **Product variants**: Prefix match (`shortCode` starts with `platformioTarget_` or `platformioTarget-`) that is NOT another device's `platformioTarget` and NOT a marketplace — shown with vendor-level prominence.
  3. **Marketplace links**: Short codes with known marketplace suffixes (e.g., `_aliexpress`, `_amazon`) or prefixes (e.g., `rokland-`, `muzi-`) — shown in smaller `.caption` font, filtered by user's locale region.
  4. **rak prefix stripping**: Targets starting with `rak` also match with the `rak` prefix stripped (e.g., `rak4631` also matches short codes containing `4631`) to handle data inconsistencies in the msh.to repo.
- Q: How should the app access the urls.json at runtime (repo is private)? → A: Bundled-only for v1. The `urls.json` is imported directly from the msh.to repo without modification. A separate `marketplaces.json` file (maintained in the app repo) defines marketplace shipping regions and match patterns.
- Q: Where in the UI should device-specific links appear? → A: As a collapsible "I want one" section (collapsed by default) within the node info/hardware detail view, with an accent-colored chevron. Vendor/variant links at the top, marketplace links below in smaller text.
- Q: How should marketplace regional availability work? → A: Each marketplace in `marketplaces.json` defines a `regions` array (ISO 3166-1 alpha-2 codes) and a `match` type (`"prefix"` or `"suffix"`). Marketplace links only show for users whose `Locale.current.region` is in the marketplace's shipping regions. Empty regions = worldwide (e.g., AliExpress).
- Q: How should devices without any matching short code be handled? → A: No "I want one" section is shown (graceful absence).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View msh.to Links for Connected Device (Priority: P1)

A user connects to a Meshtastic device and wants to find relevant msh.to links for that hardware — vendor pages, product variants, and regional marketplace listings. They navigate to the device info view and see an "I want one" collapsible section with links categorized by type.

**Why this priority**: The primary value of this feature is connecting users to relevant resources for hardware they already own or are viewing in the app, directly supporting Meshtastic's backer and partner ecosystem.

**Independent Test**: Connect to any supported device, open its hardware info view, expand the "I want one" section, and verify that vendor, variant, and marketplace links are displayed correctly.

**Acceptance Scenarios**:

1. **Given** a user is viewing node info for a Seeed SenseCAP Solar Node (platformioTarget: `seeed_solar_node`), **When** they expand the "I want one" section, **Then** they see the Pro vendor link and P1 variant link prominently at the top, with AliExpress and Amazon marketplace links below (filtered by region).
2. **Given** a user is in the US viewing a RAK WisBlock 4631 (platformioTarget: `rak4631`), **When** they expand links, **Then** they see the vendor link, plus Rokland, Muzi Works, AliExpress, and Amazon marketplace links (all ship to US).
3. **Given** a user is in Germany viewing the same RAK device, **When** they expand links, **Then** they see the vendor link, Hexaspot (ships to DE), AliExpress, and Amazon — but NOT Rokland if Rokland doesn't ship to Germany (it does in current config).
4. **Given** a user is viewing a device whose `platformioTarget` has no matching short codes, **When** they view the hardware details, **Then** no "I want one" section is shown.
5. **Given** a user is viewing `rak4631`, **When** links are shown, **Then** the `rak4631_nomadstar_meteor_pro` vendor link for a different device is NOT shown.

---

### User Story 2 - Links Stay Current via Bundled Updates (Priority: P2)

The link data stays up to date as vendors add new short codes. The bundled `urls.json` is imported from the msh.to repo without modification. A separate `marketplaces.json` defines marketplace metadata (shipping regions, match patterns) and is maintained in the app repo.

**Why this priority**: New devices and short codes are added over time. Keeping the bundled file current ensures new devices get links without code changes.

**Independent Test**: Update the bundled `urls.json`, rebuild, and verify new links appear.

**Acceptance Scenarios**:

1. **Given** a new short code is added to `urls.json`, **When** the app refreshes device data, **Then** the corresponding `DeviceLinkEntity` is created in SwiftData.
2. **Given** a short code is removed from `urls.json`, **When** the app refreshes, **Then** the orphaned `DeviceLinkEntity` is deleted.
3. **Given** a new marketplace is added to `marketplaces.json` with regions, **When** the app imports links, **Then** links for that marketplace are correctly region-filtered.

---

### User Story 3 - Browse All Device Links (Priority: P3)

A user browsing for new hardware wants to explore all available msh.to links. A section in Settings provides a directory of all imported links sorted by short code.

**Why this priority**: Supports discovery and the partner/backer ecosystem, but is secondary to the device-specific links that appear contextually.

**Independent Test**: Open the Device Links directory in Settings and verify all imported links are listed.

**Acceptance Scenarios**:

1. **Given** a user opens the Device Links directory, **When** the view loads, **Then** all imported `DeviceLinkEntity` records are listed with description and msh.to link.
2. **Given** a user taps a link, **When** the link is activated, **Then** `msh.to/{shortCode}` opens in Safari.

---

### Edge Cases

- What happens when `urls.json` is malformed? → Import fails gracefully with a log warning. Existing SwiftData records are unchanged.
- What happens when `marketplaces.json` is missing? → All non-vendor links show without region filtering.
- What happens for devices without a `platformioTarget`? → No link section shown (guard on nil).
- How are non-device short codes (discord, youtube, docs) handled? → They are stored in SwiftData but never matched to a device view since no device has those as a `platformioTarget`.
- How are short code naming inconsistencies handled? → The `rak` prefix is stripped as a fallback variant (e.g., `rak4631` → `4631`), so `rokland-4631` matches device `rak4631`.
- How are other devices' vendor links excluded? → A link with `isVendor = true` only shows if its `shortCode` exactly matches the viewed device's `platformioTarget`. Links whose short codes are other devices' `platformioTargets` are excluded from prefix matching.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST import all routes from bundled `urls.json` into `DeviceLinkEntity` SwiftData records during the device hardware refresh cycle, upserting by `shortCode`.
- **FR-002**: System MUST match links to devices using multi-tier matching: exact `platformioTarget` match (vendor), prefix match for variants, and marketplace prefix/suffix match using known marketplace keys from `marketplaces.json`.
- **FR-003**: System MUST construct link URLs as `https://msh.to/{shortCode}` — the msh.to redirect service handles routing.
- **FR-004**: System MUST use bundled data only (no runtime network fetch in v1). `urls.json` is imported from the msh.to repo; `marketplaces.json` is maintained in the app repo.
- **FR-005**: System MUST show an "I want one" collapsible section (collapsed by default) in the node info view when matching links exist, with an accent-colored chevron indicator.
- **FR-006**: System MUST categorize links as vendor/variant (prominent `.body`/`.semibold`) or marketplace (smaller `.caption`), sorted with vendor/variant first.
- **FR-007**: System MUST filter marketplace links by the user's `Locale.current.region` against the marketplace's `regions` array in `marketplaces.json`. Empty regions = worldwide.
- **FR-008**: System MUST exclude vendor links for other devices (link `isVendor = true` and `shortCode != platformioTarget`).
- **FR-009**: System MUST handle `rak` prefix inconsistencies by stripping `rak`/`rak-` from `platformioTarget` as fallback matching variants.
- **FR-010**: System MUST open msh.to link URLs in the system browser when activated.
- **FR-011**: System MUST provide a browsable directory in Settings listing all imported links.
- **FR-012**: System MUST delete orphaned `DeviceLinkEntity` records when short codes are removed from `urls.json`.

### Key Entities

- **DeviceLinkEntity** (new SwiftData model): Stores `shortCode` (unique), `originalUrl`, `linkDescription`, `isVendor` (Bool), and `regions` ([String]?, marketplace shipping regions).
- **DeviceHardwareEntity** (existing): `platformioTarget` used for matching.
- **urls.json** (bundled, from msh.to repo): Source of short codes, URLs, and descriptions. Imported without modification.
- **marketplaces.json** (bundled, app-maintained): Defines marketplace identifiers, match patterns (`"prefix"` or `"suffix"`), and shipping region arrays.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can find msh.to links for any device with matching short codes within 2 taps from the node info view.
- **SC-002**: Vendor/variant links display prominently at the top; marketplace links display smaller below.
- **SC-003**: Marketplace links are correctly filtered by the user's locale region — no links shown for marketplaces that don't ship to the user's country.
- **SC-004**: No broken links — only links with valid short codes in `urls.json` are shown.
- **SC-005**: The app functions correctly when `urls.json` or `marketplaces.json` is missing or malformed — no crashes.
- **SC-006**: The Device Links directory in Settings lists all imported short codes.

## Assumptions

- The meshtastic/msh.to repository will remain the canonical source for short code redirects.
- The `urls.json` schema (Routes array with ShortCode, OriginalUrl, Description fields) will remain stable.
- The `urls.json` file is used as-is from the msh.to repo — any naming inconsistencies (e.g., `rokland-4631` vs `rokland-rak4631`) are handled in-app via variant matching.
- The msh.to redirect service correctly routes `msh.to/{shortCode}` to the appropriate destination.
- The bundled files are updated before each release (no runtime network fetch in v1).
- Marketplace shipping regions are maintained manually in `marketplaces.json` and updated when retailers change their coverage.
- Currently configured marketplaces: Rokland (prefix, 19 regions), Hexaspot (prefix, 28 EU/EEA regions), AliExpress (suffix, worldwide), Amazon (suffix, 11 regions), Tindie (suffix, 7 regions), Muzi Works (prefix, 30 regions).

## Implementation Notes

These notes document decisions made during implementation that are not obvious from the requirements.
They are especially important for Android/cross-platform teams implementing the same feature.

### Architecture Field Must Be a String (Not an Enum)

`DeviceHardware.json` contains an `architecture` field. **Do not decode this into a closed/exhaustive enum.**

During iOS implementation, decoding `architecture` as an enum caused `decoder.decode([DeviceHardware].self)` to throw a `DecodingError` for any device using the `portduino` architecture (Linux/native targets). This silently aborted the entire `refreshBundledDevicesData()` call, meaning `importDeviceLinks()` never ran, and no `DeviceLinkEntity` records were created — so the "I want one" section never appeared.

**Fix**: Decode `architecture` as a plain `String`. Convert to a typed enum only when needed for firmware flashing, using optional/nil-safe binding so unknown values are handled gracefully. This is forward-compatible with any future architectures added to the API.

### isVendor Determination

`isVendor` is NOT determined from the URL's domain name. It is determined by checking whether the short code is itself a known `platformioTarget`:

```
platformioTargets = Set of all DeviceHardwareEntity.platformioTarget values
isVendor = platformioTargets.contains(shortCode)
```

This is the only reliable signal — vendor links in `urls.json` use the exact `platformioTarget` as their short code (e.g., `rak_wismeshtag`, `heltec-v4`). Marketplace links use a marketplace prefix/suffix (e.g., `rokland-heltec-v4`, `heltec-v4_aliexpress`).

### Refresh Lifecycle — Catalog Must Be Populated After Any Database Clear

`importDeviceLinks()` must be called any time the SwiftData store is cleared or recreated. The four trigger points in iOS are:

1. **App launch** (`MeshtasticAPI.shared` init) — `refreshBundledDevicesData()` → `importDeviceLinks()`
2. **Every BLE/TCP connect**, after config handshake completes — `refreshBundledDevicesData()` → `importDeviceLinks()`
3. **Background network refresh** (when connectivity available on connect) — `refreshDevicesAPIData()` → `importDeviceLinks()`
4. **After "Erase All App Data"** — explicit `refreshBundledDevicesData()` call → `importDeviceLinks()`

If your platform auto-reconnects or recreates the database without triggering a re-import, links will be absent until the next trigger. Add a `refreshBundledDevicesData()` call explicitly after any store reset.

### Matching Does Not Use hwModelSlug

An earlier design (see tasks.md) used `hwModelSlug` substring matching. The final implementation uses only `platformioTarget` for matching. `hwModelSlug` is not used in device link matching.

### No Many-to-Many Relationship on DeviceHardwareEntity

`DeviceHardwareEntity` has no `links` relationship. `DeviceLinksSection` uses `@Query` to load all `DeviceLinkEntity` records and filters in memory using the device's `platformioTarget`. This avoids join complexity and is fast for the current scale (~200 short codes).
