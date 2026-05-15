# Data Model: Device msh.to Links

## Architecture

No new SwiftData entities are required. The implementation uses:

1. **Bundled `urls.json`** — read-only JSON file containing all msh.to short codes
2. **In-memory `Set<String>`** — loaded once as a static property from `urls.json` `Routes[].ShortCode` values
3. **Existing `DeviceHardwareEntity.platformioTarget`** — exact-matched against the short code set

## Matching Logic

```
Device.platformioTarget == urls.json.Routes[].ShortCode
→ Link URL: https://msh.to/{platformioTarget}
```

The msh.to redirect service handles routing the short code to the correct vendor/retailer destination URL.

## JSON Source Schema (urls.json)

```json
{
  "Routes": [
    {
      "ShortCode": "heltec-v3",
      "OriginalUrl": "https://heltec.org/project/wifi-lora-32-v3/",
      "Description": "Heltec WiFi LoRa 32 V3"
    }
  ]
}
```

Decoded as:

```swift
struct MshToUrlsFile: Codable {
    let routes: [MshToRoute]
    enum CodingKeys: String, CodingKey {
        case routes = "Routes"
    }
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

Only `shortCode` is used for matching. `originalUrl` and `description` are not used by the app — the msh.to service handles the redirect.

## Validation Rules

- `platformioTarget` must exactly match a `ShortCode` — no substring, prefix, or fuzzy matching
- If `urls.json` is missing or malformed, the short code set is empty and no links are shown
- Devices without a `platformioTarget` never show links

## Previous Design (Superseded)

The original design used a `DeviceLinkEntity` SwiftData model with many-to-many relationships, substring matching on `hwModelSlug`, vendor priority sorting, and locale-aware ordering. This was replaced with the simpler exact-match approach since each device maps to exactly one msh.to link via its `platformioTarget`.
