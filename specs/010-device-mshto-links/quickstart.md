# Quickstart: Device msh.to Links

## Prerequisites

- Xcode (latest stable)
- A copy of `urls.json` from the meshtastic/msh.to repository placed at `Meshtastic/Resources/urls.json`
- Run `scripts/setup-hooks.sh` for SwiftLint pre-commit hook

## Build & Run

1. Open `Meshtastic.xcworkspace` in Xcode
2. Select the `Meshtastic` scheme targeting any iOS Simulator
3. Build and run (⌘R)

The app will automatically import `urls.json` during its device hardware refresh on first launch.

## Verify

1. Wait for device hardware to load (check console for `Logger.services` output)
2. Navigate to any node → Node Info view
3. If the device has matching links, a "Links" section appears with tappable rows
4. Each row shows the link description and opens in Safari on tap

## Run Tests

1. Open `Meshtastic.xctestplan`
2. Run all tests (⌘U)
3. `DeviceLinkTests` validates import logic, substring matching, and vendor priority sorting

## Key Files

| File | Purpose |
|------|---------|
| `Meshtastic/Model/DeviceLinkEntity.swift` | SwiftData model |
| `Meshtastic/API/MeshtasticAPI.swift` | Import logic (extended) |
| `Meshtastic/Views/Nodes/Helpers/DeviceLinksSection.swift` | UI for node info |
| `Meshtastic/Views/Settings/DeviceLinkDirectory.swift` | Browsable directory |
| `Meshtastic/Resources/urls.json` | Bundled link data |
| `MeshtasticTests/DeviceLinkTests.swift` | Unit tests |
