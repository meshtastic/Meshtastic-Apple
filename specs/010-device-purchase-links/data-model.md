# Data Model: Device msh.to Links

## Entities

### DeviceHardwareLinkEntity (new)

| Field | Type | Description |
|-------|------|-------------|
| shortCode | String | Unique identifier from msh.to (e.g., "rokland-rak4631") |
| url | String | Destination URL |
| linkDescription | String | Human-readable description (e.g., "Rokland RAK4631 Starter Kit") |
| device | DeviceHardwareEntity? | Optional relationship to matched device |

**Constraints**:
- `shortCode` is unique across all entries
- `url` must be a valid URL string
- `device` is nil for non-device links (social media, docs, etc.)

### DeviceHardwareEntity (modified)

| Field | Type | Description |
|-------|------|-------------|
| links | [DeviceHardwareLinkEntity] | NEW — inverse relationship, cascade delete |
| *(all existing fields unchanged)* | | |

## Relationships

```
DeviceHardwareEntity 1 ──── * DeviceHardwareLinkEntity
                     (links)     (device)
```

- One device can have many links (multiple vendors/retailers)
- A link can have zero or one device (non-device links have nil device)
- Delete rule: cascade — deleting a device deletes its links

## Matching Logic

```
For each route in urls.json:
  For each device in DeviceHardwareEntity:
    If route.shortCode contains device.hwModelSlug:
      Associate route → device (prefer longest slug match)
```

## Vendor Priority Model

| Tier | Domain Pattern | Examples |
|------|---------------|----------|
| 1 — Manufacturer | Known manufacturer domains | store.rakwireless.com, heltec.org, lilygo.cc, seeedstudio.com, elecrow.com |
| 2 — Regional Retailer | Known retailer domains | store.rokland.com (US), hexaspot.com (EU) |
| 3 — Global Marketplace | Marketplace domains | aliexpress.com, amazon.com, tindie.com |

Within tier 2, user's `Locale.current.region` determines ordering preference.

## JSON Source Schema

```json
{
  "Routes": [
    {
      "ShortCode": "string — unique identifier",
      "OriginalUrl": "string — destination URL",
      "Description": "string — human-readable label"
    }
  ]
}
```
