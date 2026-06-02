# Data Model: Device msh.to Links

## Architecture

The implementation uses two bundled JSON files and one new SwiftData entity:

1. **Bundled `urls.json`** — imported from the meshtastic/msh.to repo without modification. Contains all short codes, destination URLs, and descriptions.
2. **Bundled `marketplaces.json`** — maintained in the app repo. Defines marketplace identifiers, match patterns (`"prefix"` or `"suffix"`), and ISO 3166-1 shipping region arrays.
3. **`DeviceLinkEntity`** (SwiftData) — one record per short code. Upserted from `urls.json` on every device hardware refresh cycle.

## SwiftData Entities

### DeviceLinkEntity

```swift
@Model
final class DeviceLinkEntity {
    @Attribute(.unique) var shortCode: String        // e.g. "rak_wismeshtag", "rokland-heltec-v3"
    var originalUrl: String                           // destination URL from urls.json
    var linkDescription: String?                      // human-readable label
    var isVendor: Bool                                // true when shortCode == a device's platformioTarget
    var regions: [String]?                            // ISO 3166-1 codes (nil = vendor, [] = worldwide)
}
```

**`isVendor` determination**: During `importDeviceLinks()`, all `DeviceHardwareEntity.platformioTarget` values are fetched into a `Set<String>`. A link is vendor if its `shortCode` is in that set (i.e., it IS a known device target).

**`regions` semantics**:
- `nil` — vendor link; not region-filtered
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

### urls.json

```json
{
  "Routes": [
    {
      "ShortCode": "rak_wismeshtag",
      "OriginalUrl": "https://store.rakwireless.com/...",
      "Description": "RAK WisMesh Tag"
    }
  ]
}
```

Swift decoding:

```swift
struct MshToUrlsFile: Codable {
    let routes: [MshToRoute]
    enum CodingKeys: String, CodingKey { case routes = "Routes" }
}
struct MshToRoute: Codable {
    let shortCode: String
    let originalUrl: String
    let description: String?
    enum CodingKeys: String, CodingKey {
        case shortCode = "ShortCode"
        case originalUrl = "OriginalUrl"
        case description = "Description"
    }
}
```

### marketplaces.json

```json
{
  "rokland":    { "match": "prefix", "regions": ["AU","AT","BE","CA","DE","FR","GB","IE","JP","NL","NZ","NO","PK","ES","SE","CH","US"] },
  "hexaspot":   { "match": "prefix", "regions": ["AT","BE","BG","CY","CZ","DE","DK","EE","ES","FI","FR","GR","HR","HU","IE","IT","LT","LU","LV","MT","NL","NO","PL","PT","RO","SE","SI","SK"] },
  "aliexpress": { "match": "suffix", "regions": [] },
  "amazon":     { "match": "suffix", "regions": ["AU","CA","FR","DE","IE","JP","NL","ES","SE","GB","US"] },
  "tindie":     { "match": "suffix", "regions": ["US","CA","GB","DE","FR","AU","NL"] },
  "muzi":       { "match": "prefix", "regions": ["AU","AT","BE","CA","CZ","DK","FI","FR","DE","HK","IN","IE","IL","IT","JP","MY","NL","NZ","NO","PL","PT","SG","KR","ES","SE","CH","TW","AE","GB","US"] }
}
```

For `"prefix"` match: `shortCode.hasPrefix(marketplaceKey)` — e.g., `"rokland-heltec-v3"` matches `"rokland"`.  
For `"suffix"` match: `shortCode.hasSuffix("_\(key)")` or `shortCode.hasSuffix("-\(key)")` — e.g., `"heltec-v3_aliexpress"` matches `"aliexpress"`.

## importDeviceLinks() Algorithm

Called at the end of both `refreshBundledDevicesData()` (bundled JSON) and `refreshDevicesAPIData()` (network).

```
1. Load and decode urls.json → [MshToRoute]
2. Load and decode marketplaces.json → [String: MshToMarketplace]
3. Fetch all DeviceHardwareEntity.platformioTarget values → Set<String> (platformioTargets)
4. For each route in urls.json:
   a. isVendor = platformioTargets.contains(route.shortCode)
   b. If NOT vendor: scan marketplaces for prefix/suffix match → assign regions
      (nil regions if no marketplace match; [] if marketplace has no regions)
   c. Upsert DeviceLinkEntity by shortCode (update existing, insert new)
5. Fetch all existing DeviceLinkEntity records
6. Delete any whose shortCode is NOT in the current urls.json import set (orphan cleanup)
7. Save context
```

## DeviceLinksSection Matching Algorithm

`DeviceLinksSection` receives a `platformioTarget: String` and filters `@Query var allLinks: [DeviceLinkEntity]`:

```
For each link in allLinks:
  1. Vendor exclusion: if link.isVendor && link.shortCode != platformioTarget → EXCLUDE
  2. Exact vendor match: link.shortCode == platformioTarget → INCLUDE
  3. Prefix match: link.shortCode.hasPrefix(platformioTarget + "-") or ("_") → INCLUDE
     (catches product variants, e.g., "rak4631_nomadstar_meteor_pro" for target "rak4631")
  4. Marketplace prefix match: any marketplace key where
       link.shortCode.hasPrefix(key + "-") or hasSuffix("_" + platformioTarget) → INCLUDE
  5. Region filter (marketplace links only):
       if link.regions == nil → pass (vendor)
       if link.regions == [] → pass (worldwide)
       if Locale.current.region?.identifier in link.regions → pass
       else → EXCLUDE
```

Sort: vendor/variant links first (isVendor or not-a-marketplace), marketplace links after.  
Display: vendor/variant → `.body` / `.semibold`; marketplace → `.subheadline` / `.regular`.

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
