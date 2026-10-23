# Data Model: Device msh.to Links

## Architecture

> **Updated 2026-06-09:** migrated to the structured msh.to API. The catalog is now a single
> document (`{ Routes, Marketplaces }`) fetched at runtime, with classification (`Type`) and device
> association (`Targets`) carried inline — replacing the old two-file, heuristic-matching design.

1. **msh.to API** (`https://msh.to/api/urls`) — the canonical source. One document containing the
   `Routes` array (short codes, descriptions, `Type`, `Targets`) and a `Marketplaces` region map.
2. **Bundled `urls.json`** — mirrors the API document; used as an offline fallback when the network
   is unavailable. (`marketplaces.json` is deprecated — regions are embedded in the response.)
3. **`DeviceLinkEntity`** (SwiftData) — one record per short code. Upserted from the catalog on every
   device hardware refresh cycle.

## SwiftData Entities

### DeviceLinkEntity

```swift
@Model
final class DeviceLinkEntity {
    @Attribute(.unique) var shortCode: String        // e.g. "rak_wismeshtag", "rokland-rak4631"
    var originalUrl: String                           // "https://msh.to/{shortCode}" redirect
    var linkDescription: String?                      // human-readable label
    var isVendor: Bool                                // route Type == "Vendor"
    var isMarketplace: Bool                           // route Type == "Marketplace"
    var targets: [String]                             // platformioTargets this link applies to
    var regions: [String]?                            // ISO 3166-1 codes (nil = not a marketplace, [] = worldwide)
}
```

**`isVendor` / `isMarketplace` determination**: taken directly from the route `Type` field
(`"Vendor"` / `"Marketplace"`). `"Internal"` (or any unknown type) sets both to `false` and carries
no `targets`, so it never matches a device.

**`targets` semantics**: the device association. A link shows for a device iff
`targets.contains(platformioTarget)`. There is no prefix/variant/`rak`-strip matching.

**`regions` semantics**:
- `nil` — vendor or internal link; not region-filtered
- `[]` (empty array) — worldwide marketplace (e.g., AliExpress)
- `["US", "CA", ...]` — marketplace limited to listed countries

### DeviceHardwareEntity (relevant fields)

```swift
var hwModel: Int64                    // matches node.user?.hwModelId
var hwModelSlug: String?              // e.g. "WISMESH_TAG"
var platformioTarget: String?         // e.g. "rak_wismeshtag" — primary matching key
var architecture: String?             // e.g. "esp32", "nrf52840", "portduino"
var displayName: String?
var activelySupported: Bool
var supportLevel: Int                 // 0=discontinued, 1=flagship, 2=niche, 3=legacy
```

> **Critical**: `architecture` is stored as `String`, not an enum. The `DeviceHardware` JSON
> struct (used only for decoding) must also use `String` for this field — see
> [Architecture Decode Robustness](#architecture-decode-robustness) below.

## JSON Source Schemas

### `https://msh.to/api/urls` (and bundled `urls.json`)

```json
{
  "Routes": [
    { "ShortCode": "github",            "Description": "Meshtastic GitHub",  "Type": "Internal" },
    { "ShortCode": "rak4631",           "Description": "WisMesh RAK4631",    "Type": "Vendor",      "Targets": ["rak4631"] },
    { "ShortCode": "rokland-wismesh-tag","Description": "Rokland WisMesh Tag","Type": "Marketplace", "Targets": ["rak_wismeshtag"] }
  ],
  "Marketplaces": {
    "rokland":    { "Regions": ["AU","AT","BE","CA","DE","FR","GB","IE","JP","NL","NZ","NO","PK","ES","SE","CH","US","DK","EC"] },
    "hexaspot":   { "Regions": ["AT","BE","BG","CY","CZ","DE","DK","EE","ES","FI","FR","GR","HR","HU","IE","IT","LT","LU","LV","MT","NL","NO","PL","PT","RO","SE","SI","SK"] },
    "aliexpress": { "Regions": [] },
    "amazon":     { "Regions": ["AU","CA","FR","DE","IE","JP","NL","ES","SE","GB","US"] },
    "tindie":     { "Regions": ["US","CA","GB","DE","FR","AU","NL"] },
    "muzi":       { "Regions": ["AU","AT","BE","CA","CZ","DK","FI","FR","DE","HK","IN","IE","IL","IT","JP","MY","NL","NZ","NO","PL","PT","SG","KR","ES","SE","CH","TW","AE","GB","US"] }
  }
}
```

`Type` is one of `"Internal"`, `"Vendor"`, `"Marketplace"`. `Targets` lists the device
`platformioTarget` values a route applies to (absent/empty for `Internal`). There is no
`OriginalUrl` — links open as `https://msh.to/{ShortCode}`. The `Marketplaces` object has no `match`
field; a route's marketplace is found by matching a key as a **prefix or suffix** of the short code
(e.g. `"rokland-…"` or `"…-aliexpress"`), and its `Regions` attach to the link.

Swift decoding:

```swift
enum MshToLinkType: String, Codable {
    case internalLink = "Internal", vendor = "Vendor", marketplace = "Marketplace"
}
struct MshToUrlsFile: Codable {
    let routes: [MshToRoute]
    let marketplaces: [String: MshToMarketplace]
    enum CodingKeys: String, CodingKey { case routes = "Routes"; case marketplaces = "Marketplaces" }
}
struct MshToRoute: Codable {
    let shortCode: String
    let description: String?
    let type: MshToLinkType        // unknown/missing → .internalLink
    let targets: [String]          // missing → []
    enum CodingKeys: String, CodingKey {
        case shortCode = "ShortCode"; case description = "Description"
        case type = "Type"; case targets = "Targets"
    }
}
struct MshToMarketplace: Codable {
    let regions: [String]
    enum CodingKeys: String, CodingKey { case regions = "Regions" }
}
```

## importDeviceLinks() Algorithm

Called at the end of both `refreshBundledDevicesData()` and `refreshDevicesAPIData()`.

```
1. Load the catalog via loadMshToUrls():
   a. GET https://msh.to/api/urls (15s timeout). On 2xx + decode success → use it.
   b. Otherwise fall back to the bundled urls.json (same { Routes, Marketplaces } shape).
2. For each route:
   a. isVendor      = route.Type == "Vendor"
      isMarketplace = route.Type == "Marketplace"
   b. If marketplace: find a Marketplaces key that is a prefix or suffix of the short code
      → regions = that marketplace's Regions  (nil if none; [] = worldwide)
   c. originalUrl = "https://msh.to/{shortCode}"
   d. Upsert DeviceLinkEntity by shortCode, storing isVendor/isMarketplace/targets/regions.
3. Fetch all existing DeviceLinkEntity records.
4. Delete any whose shortCode is NOT in the current import set (orphan cleanup).
5. Save context.
```

No `DeviceHardwareEntity` fetch is needed any more — classification and association come from the
route itself (`Type` / `Targets`).

## DeviceLinksSection Matching Algorithm

`DeviceLinksSection` receives a `platformioTarget: String` and filters `@Query var allLinks: [DeviceLinkEntity]`:

```
For each link in allLinks:
  1. Association: if NOT link.targets.contains(platformioTarget) → EXCLUDE
  2. Region filter (marketplace links only):
       if !link.isMarketplace        → pass (vendor)
       if link.regions is nil/empty   → pass (worldwide)
       if Locale.current.region in link.regions → pass
       else → EXCLUDE
```

Sort: vendor links first (`!isMarketplace`), marketplace links after; alphabetical within each group.

Display: vendor → `.body` / `.semibold`; marketplace → `.subheadline` / `.regular`.

## Architecture Decode Robustness

> **This is a known cross-platform pitfall — Android must handle this too.**

The `DeviceHardware.json` file contains an `architecture` field that is a free-form string.
Known values: `esp32`, `esp32-c3`, `esp32-c6`, `esp32-s3`, `nrf52840`, `rp2040`, `portduino`.

**Do NOT decode `architecture` into a closed enum.** If `portduino` (or any future value) is
absent from the enum, the entire JSON array decode fails and no device records are created —
which means `importDeviceLinks()` never runs and no `DeviceLinkEntity` records are inserted.

The fix: decode `architecture` as a plain `String`. Convert to a typed enum only at the point
of use (e.g., firmware flashing), using optional binding (`Architecture(rawValue: arch) ?? nil`)
so unknown values are handled gracefully rather than throwing.

## Refresh Lifecycle

`importDeviceLinks()` is called in these scenarios:

| Trigger | Path |
|---------|------|
| App launch / `MeshtasticAPI.shared` init | `refreshBundledDevicesData()` → `importDeviceLinks()` |
| Every BLE/TCP connect (config complete) | `refreshBundledDevicesData()` → `importDeviceLinks()` |
| Background network refresh (on connect, when enabled) | `refreshDevicesAPIData()` → `importDeviceLinks()` |
| After "Erase All App Data" | explicit `refreshBundledDevicesData()` call → `importDeviceLinks()` |

This ensures `DeviceLinkEntity` records are always repopulated after any database clear,
even without a network connection.
