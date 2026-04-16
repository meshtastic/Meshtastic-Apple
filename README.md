# Meshtastic Apple Clients

## Overview

SwiftUI client applications for iOS, iPadOS and macOS.

## Getting Started

This project always uses the latest release version of XCode.

1. Clone the repo.
    ```sh
    git clone git@github.com:meshtastic/Meshtastic-Apple.git
    ```
2. Open the local directory.
    ```sh
    cd Meshtastic-Apple
    ```
3. Set up git hooks to automatically lint the project when you commit changes.
    ```sh
    ./scripts/setup-hooks.sh
    ```
4. Open `Meshtastic.xcworkspace`
    ```sh
    open Meshtastic.xcworkspace
    ```
5. Build and run the `Meshtastic` target.

## Technical Standards

### Supported Operating Systems

The last two major operating system versions are supported on iOS, iPadOS and macOS.

### Code Standards

- Use SwiftUI
- Use SFSymbols for icons
- Use Core Data for persistence

## Updating Protobufs:

1. run
```bash
./scripts/gen_protos.sh
```
2. Build, test, and commit the changes.

## Deep Links

The app supports deep links using the `meshtastic:///` URL scheme, for use with shortcuts, intents, and web pages.

### Messages

| URL | Description |
|-----|-------------|
| `meshtastic:///messages` | Messages tab |
| `meshtastic:///messages?channelId={channelId}&messageId={messageId}` | Channel messages (`messageId` is optional) |
| `meshtastic:///messages?userNum={userNum}&messageId={messageId}` | Direct messages (`messageId` is optional) |

### Connect

| URL | Description |
|-----|-------------|
| `meshtastic:///connect` | Connect tab |

### Nodes

| URL | Description |
|-----|-------------|
| `meshtastic:///nodes` | Nodes tab |
| `meshtastic:///nodes?nodenum={nodenum}` | Selected node |

### Mesh Map

| URL | Description |
|-----|-------------|
| `meshtastic:///map` | Map tab |
| `meshtastic:///map?nodenum={nodenum}` | Node on map |
| `meshtastic:///map?waypointId={waypointId}` | Waypoint on map |

### Settings

Each settings item has an associated deep link. No parameters are supported for settings URLs.

| URL | Description |
|-----|-------------|
| `meshtastic:///settings/about` | About Meshtastic |
| `meshtastic:///settings/appSettings` | App Settings |
| `meshtastic:///settings/routes` | Routes |
| `meshtastic:///settings/routeRecorder` | Route Recorder |
| **Radio Config** | |
| `meshtastic:///settings/lora` | LoRa Config |
| `meshtastic:///settings/channels` | Channels |
| `meshtastic:///settings/security` | Security Config |
| `meshtastic:///settings/shareQRCode` | Share QR Code |
| **Device Config** | |
| `meshtastic:///settings/user` | User Config |
| `meshtastic:///settings/bluetooth` | Bluetooth Config |
| `meshtastic:///settings/device` | Device Config |
| `meshtastic:///settings/display` | Display Config |
| `meshtastic:///settings/network` | Network Config |
| `meshtastic:///settings/position` | Position Config |
| `meshtastic:///settings/power` | Power Config |
| **Module Config** | |
| `meshtastic:///settings/ambientLighting` | Ambient Lighting |
| `meshtastic:///settings/cannedMessages` | Canned Messages |
| `meshtastic:///settings/detectionSensor` | Detection Sensor |
| `meshtastic:///settings/externalNotification` | External Notification |
| `meshtastic:///settings/mqtt` | MQTT |
| `meshtastic:///settings/paxCounter` | Pax Counter |
| `meshtastic:///settings/rangeTest` | Range Test |
| `meshtastic:///settings/ringtone` | Ringtone |
| `meshtastic:///settings/serial` | Serial |
| `meshtastic:///settings/storeAndForward` | Store & Forward |
| `meshtastic:///settings/telemetry` | Telemetry |
| **TAK** | |
| `meshtastic:///settings/tak` | TAK Config |
| **Tools** | |
| `meshtastic:///settings/tools` | Tools |
| **Logging** | |
| `meshtastic:///settings/debugLogs` | Debug Logs |
| **Developers** | |
| `meshtastic:///settings/appFiles` | App Files |
| `meshtastic:///settings/firmwareUpdates` | Firmware Updates |

## Release Process

For more information on how a new release of Meshtastic is managed, please refer to [RELEASING.md](./RELEASING.md)

## License

This project is licensed under the GPL v3. See the [LICENSE](LICENSE) file for details.
