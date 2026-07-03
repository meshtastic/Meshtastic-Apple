# Research: Device msh.to Links

## R-001: urls.json Schema

**Decision**: Parse a `Routes` JSON array where each entry has `ShortCode` (String), `OriginalUrl` (String), and `Description` (String).

**Rationale**: The spec explicitly states this schema (Assumptions section). The `ShortCode` serves as a unique identifier and is the key for substring matching against `hwModelSlug`.

**Alternatives considered**:
- Custom API endpoint: Rejected — spec requires bundled-only in v1.
- Embedding link data in DeviceHardware.json: Rejected — separate concerns, different update cadence.

## R-002: Substring Matching Strategy

**Decision**: For each link's `ShortCode`, check if it contains any known `hwModelSlug` value (case-insensitive). Associate the link with all matching devices.

**Rationale**: Spec clarification says "associate links whose shortCode contains the device's hwModelSlug" (e.g., `rokland-rak4631` contains `rak4631`).

**Alternatives considered**:
- Prefix matching only: Rejected — vendor prefixes like `rokland-` come before the slug.
- Regex patterns: Rejected — overcomplicated for simple contains check.
- Exact match: Rejected — short codes embed vendor + device slug.

## R-003: Vendor Priority Ordering

**Decision**: Static priority list based on URL domain classification:
1. Manufacturer direct (rakwireless.com, heltec.org, lilygo.cc, seeedstudio.com, elecrow.com)
2. Regional retailers preferred for user locale (rokland.com for US, hexaspot.com for EU)
3. Global marketplaces (aliexpress.com, amazon.com)

Extract vendor category from `URL.host` of `OriginalUrl`. Locale detection via `Locale.current.region?.identifier`.

**Rationale**: Spec FR-009 requires this ordering. Domain extraction is simple and reliable.

**Alternatives considered**:
- Metadata field in urls.json for vendor type: Not available in current schema.
- Manual vendor mapping per ShortCode prefix: More fragile than domain-based.

## R-004: SwiftData Schema Migration

**Decision**: Add `DeviceLinkEntity` as a new model and add a relationship on `DeviceHardwareEntity`. Create `MeshtasticSchemaV2` with a lightweight migration stage.

**Rationale**: Constitution II requires SwiftData with `VersionedSchema`. Adding a new entity with a new optional relationship is a lightweight migration.

**Alternatives considered**:
- Store links in UserDefaults/plist: Rejected — violates Constitution II.
- Store as JSON blob on DeviceHardwareEntity: Rejected — loses queryability for the directory view.

## R-005: Import Timing

**Decision**: Import urls.json in `MeshtasticAPI.refreshDevicesAPIData()` after device entities are saved, reusing the same `MainActor` context pattern.

**Rationale**: The spec says "during the device hardware refresh cycle." The existing `refreshDevicesAPIData()` already loads bundled fallback data and saves to mainContext. Adding link import after Phase 2 (device save) ensures devices exist before association.

**Alternatives considered**:
- Separate refresh method: Adds complexity; links depend on devices existing first.
- Lazy load on view appearance: Doesn't meet SC-003 (automatic refresh).

## R-006: Non-Device Links

**Decision**: Store all links from urls.json, even those that don't match any device `hwModelSlug`. These have an empty `devices` relationship and appear in the browsable directory (P3).

**Rationale**: FR-007 requires retaining non-device links for the directory view.
