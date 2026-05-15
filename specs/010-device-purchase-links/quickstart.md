# Quickstart: Device msh.to Links

## Prerequisites

- Xcode (latest release)
- The meshtastic/msh.to repo cloned (for updating the bundled JSON)
- A connected Meshtastic device (for testing link display)

## Setup

1. Run `scripts/update-device-links.sh` to fetch the latest `urls.json` into `Meshtastic/Resources/DeviceLinks.json`
2. Build and run the app — links are imported during the device hardware refresh cycle on launch

## Verify

1. Connect to any supported device (e.g., RAK4631, Heltec V3, T-Deck)
2. Navigate to the node info view for that device
3. Scroll to the "Links" section
4. Verify links are displayed, ordered by vendor priority
5. Tap a link — it should open in Safari

## Run Tests

```bash
# From Xcode: ⌘U or Product → Test
# Tests are in MeshtasticTests/DeviceLinksTests.swift
```

## Update Bundled Links

```bash
# Refresh the bundled DeviceLinks.json from msh.to repo
bash scripts/update-device-links.sh
```

## Key Files

| File | Purpose |
|------|---------|
| `Meshtastic/Resources/DeviceLinks.json` | Bundled msh.to link data |
| `Meshtastic/Model/DeviceHardwareLinkEntity.swift` | SwiftData model |
| `Meshtastic/API/MeshtasticAPI.swift` | Import + matching logic |
| `Meshtastic/Extensions/DeviceHardwareLinkEntity+Priority.swift` | Vendor priority sorting |
| `Meshtastic/Views/Nodes/Helpers/NodeInfoItem.swift` | UI display |
| `scripts/update-device-links.sh` | CI/build script to refresh bundled JSON |
