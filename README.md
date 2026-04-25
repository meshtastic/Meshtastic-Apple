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
| **Logging** | |
| `meshtastic:///settings/debugLogs` | Debug Logs |
| **Developers** | |
| `meshtastic:///settings/appFiles` | App Files |
| `meshtastic:///settings/firmwareUpdates` | Firmware Updates |

## CarPlay

The app supports Apple CarPlay for **hands-free mesh messaging** while driving. The CarPlay interface integrates with the iOS messaging system and Siri so that users can send and receive Meshtastic messages without looking at their phone.

### Requirements

- iPhone running iOS 16 or later
- A supported CarPlay head unit or the CarPlay Simulator in Xcode
- A Meshtastic device connected via Bluetooth, TCP, or serial
- Siri enabled — the app requests Siri authorization during onboarding and again on subsequent launches

### Interface

The CarPlay screen presents a **two-tab interface**:

| Tab | Description |
|-----|-------------|
| **Channels** | Lists all active mesh channels |
| **Direct Messages** | Lists recent and favorite contacts |

When no Meshtastic device is connected, both tabs show a **"Not Connected"** status item with a prompt to open the Meshtastic app.

#### Channels Tab

Each channel row shows:
- The channel name (or "Primary Channel" for index 0)
- An unread message badge when there are unread messages
- "Primary" or "Ch N" as detail text

Tapping a channel row starts a Siri compose session for that channel.

#### Direct Messages Tab

The Direct Messages tab is divided into two sections:

- **Favorites** — Nodes marked as favorites (⭐ icon), sorted by last heard
- **Recent** — All other messageable contacts with history, sorted by last heard (capped at 24 entries)

Each contact row shows:
- Contact name and a person icon
- Unread message count when applicable
- Time since last heard (e.g., "Just now", "5m ago", "2h ago", "3d ago")

### Siri Voice Commands

Use these Siri voice commands in CarPlay to interact with Meshtastic:

| Voice Command | Example Phrase | Description |
|---|---|---|
| Send Message | "Send a message on Meshtastic" | Composes and sends a text message to a contact or channel |
| Search Messages | "Search Meshtastic messages" | Searches message history |
| Mark as Read | "Mark Meshtastic message as read" | Marks a conversation as read |

**Limitations:**
- Messages are limited to **200 bytes** (UTF-8). Siri will not send messages that exceed this limit.
- Only a **single recipient** per message is supported — no group direct messages.
- Emoji-only messages and admin messages are excluded from CarPlay.

### Incoming Message Announcements

When CarPlay is connected and **Announce Notifications** is enabled in iOS Settings → Siri, Siri reads incoming Meshtastic messages aloud. Only non-emoji, non-admin text messages trigger announcements.

Up to 50 unread messages that arrived before the CarPlay session started are donated to Siri at connection time so they can be read back on demand.

### Live Activity

When a Meshtastic device connects during a CarPlay session, a **Dynamic Island / Lock Screen Live Activity** starts automatically (iOS only, not available on macOS). It displays:

- Node name and short name
- Uptime, channel utilization, and air-time TX percentage
- Packets sent, received, and relay statistics
- Online and total node counts
- A 15-minute countdown timer synced with the telemetry reporting interval

The Live Activity ends automatically when CarPlay disconnects.

### Architecture Notes (For Developers)

| Component | File | Description |
|---|---|---|
| `CarPlaySceneDelegate` | `Meshtastic/CarPlay/CarPlaySceneDelegate.swift` | `CPTemplateApplicationSceneDelegate` that builds and manages the two-tab UI |
| `CarPlayIntentDonation` | `Meshtastic/CarPlay/CarPlayIntentDonation.swift` | Donates incoming and outgoing `INSendMessageIntent` interactions so conversations appear in CarPlay Messages and Siri can read them aloud |
| `SendMessageIntentHandler` | `Meshtastic/Intents/SendMessageIntentHandler.swift` | Handles `INSendMessageIntent` — resolves recipients/channels and sends the message over the active transport |
| `SearchForMessagesIntentHandler` | `Meshtastic/Intents/SearchForMessagesIntentHandler.swift` | Handles `INSearchForMessagesIntent` |
| `SetMessageAttributeIntentHandler` | `Meshtastic/Intents/SetMessageAttributeIntentHandler.swift` | Handles `INSetMessageAttributeIntent` (mark as read) |
| `IntentHandler` | `Meshtastic/Intents/IntentHandler.swift` | Routes `INIntent`s to the appropriate handler |

The scene delegate subscribes to `AccessoryManager.shared.$isConnected` with a 300 ms debounce and calls `updateSections(_:)` on the existing `CPListTemplate` instances (rather than rebuilding the whole template tree) to minimise flicker during reconnects.

Intent donations are de-duplicated per CarPlay session using an in-memory set to avoid repeated IPC calls to the intents daemon on every list refresh.


## Release Process

For more information on how a new release of Meshtastic is managed, please refer to [RELEASING.md](./RELEASING.md)

## License

This project is licensed under the GPL v3. See the [LICENSE](LICENSE) file for details.
