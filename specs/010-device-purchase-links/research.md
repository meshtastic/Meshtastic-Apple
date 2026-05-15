# Research: Device msh.to Links

## Decision 1: Link-to-Device Matching Strategy

**Decision**: Substring matching — a link is associated with a device if the link's `ShortCode` contains the device's `hwModelSlug`.

**Rationale**: The msh.to urls.json uses a convention where vendor-specific links prepend the vendor name to the device slug (e.g., `rokland-rak4631`, `hexaspot-4631`, `aliexpress-rak4631`). Substring matching captures all variants without maintaining a manual mapping table.

**Alternatives considered**:
- Exact match only: Too restrictive — only ~30% of device links would match.
- Manual mapping table: Maintenance burden, would need updating with every new link.
- Regex patterns: Over-engineered for the current data format.

**Edge case handling**: When a shortCode matches multiple device slugs (e.g., `rak19007` could substring-match both `rak1900` and `rak19007`), prefer the longest matching slug. This ensures specificity.

## Decision 2: Data Source Access Strategy

**Decision**: Bundled JSON file only (v1). Updated via a CI/build script (`scripts/update-device-links.sh`) that clones the msh.to repo and copies `urls.json` to `Meshtastic/Resources/DeviceLinks.json`.

**Rationale**: The msh.to repository is currently private. Adding authentication tokens to the app binary is a security risk. A bundled file ensures the feature works offline and avoids API rate limiting.

**Alternatives considered**:
- Runtime network fetch with auth token: Security risk, requires Secrets.json management.
- GitHub Pages public endpoint: Not available until repo is made public.
- Git submodule: Heavyweight for a single JSON file.

**Future path**: When the repo is made public or a CDN is configured, add a runtime fetch with the bundled file as fallback (same pattern as `DeviceHardware.json`).

## Decision 3: Vendor Priority Ordering

**Decision**: Static priority tiers derived from URL domain, with locale-based regional preference within tier 2.

**Priority tiers**:
1. **Manufacturer direct**: `store.rakwireless.com`, `heltec.org`, `lilygo.cc`, `www.seeedstudio.com`, `www.elecrow.com`, `shop.uniteng.com`, `muzi.works`, `nomadstar.ch`
2. **Regional retailers** (ordered by locale):
   - US locale: `store.rokland.com` first
   - EU locale: `hexaspot.com` first
   - Other: alphabetical
3. **Global marketplaces**: `aliexpress.com`, `amazon.com`, `www.tindie.com`

**Rationale**: Manufacturer links provide the most authoritative product information. Regional retailers offer locale-appropriate shipping and pricing. Global marketplaces are last resort.

**Implementation**: Extract domain from URL, match against a static dictionary mapping domains → (tier, vendor name). Sort by tier, then by locale preference within tier 2, then alphabetically.

## Decision 4: SwiftData Schema Approach

**Decision**: New `DeviceHardwareLinkEntity` with a relationship to existing `DeviceHardwareEntity`. Lightweight migration (additive — new entity + new relationship).

**Rationale**: Follows the existing pattern used by `DeviceHardwareImageEntity` and `DeviceHardwareTagEntity`. Relationship allows `@Query` in views with predicate filtering by device.

**Alternatives considered**:
- Store links as JSON blob on DeviceHardwareEntity: Loses queryability, harder to update individual links.
- Separate non-SwiftData storage (UserDefaults, file): Inconsistent with architecture, loses relationship benefits.

## Decision 5: Bundle Update Script

**Decision**: A bash script `scripts/update-device-links.sh` that:
1. Clones (or pulls) the msh.to repo to a temp directory
2. Copies `urls.json` to `Meshtastic/Resources/DeviceLinks.json`
3. Optionally run as part of the existing `download_images.py` build phase or as a standalone pre-build step

**Rationale**: Keeps the bundled file fresh without manual intervention. Same pattern as `DeviceHardware.json` which is updated by `scripts/download_images.py`.
