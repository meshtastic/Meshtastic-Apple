# Device Onboarding

The device-onboarding flow is the first thing a new user sees after installing the Meshtastic app. It walks through every system permission the app needs, explains why each one is useful, and provides a single-tap path to the OS permission dialog for each one.

## Overview

On first launch, `ContentView` detects `UserDefaults.firstLaunch == true` and presents `DeviceOnboarding` as a full-screen sheet. The sheet is **interactively non-dismissible** on the welcome screen — the user must tap "Get started" to proceed. After the final step the sheet is dismissed and `UserDefaults.firstLaunch` is set to `false`; `AccessoryManager.startDiscovery()` is then called so the app begins scanning for nearby nodes.

The flow can also be re-shown at any time by setting `UserDefaults.showDeviceOnboarding = true`, which `ContentView` observes via `onChange`.

## Architecture

The feature lives in a single SwiftUI `View`:

```
Meshtastic/Views/Onboarding/DeviceOnboarding.swift
```

### `SetupGuide` Enum

```swift
enum SetupGuide: Hashable {
    case notifications
    case location
    case backgroundActivity
    case localNetwork
    case bluetooth
    case siri
}
```

Each case corresponds to one step in the flow. The enum is `Hashable` so it can be used as the type in `NavigationStack`'s `path`.

### Navigation Stack

`DeviceOnboarding` uses a `NavigationStack(path: $navigationPath)` rooted at the welcome screen. Each step is pushed onto `navigationPath` rather than using a separate sheet, which gives the user a native back-swipe affordance on every step after the first.

Navigation advances via `goToNextStep(after:)`, an `async` method that:

1. Reads the current `UNAuthorizationStatus` from `UNUserNotificationCenter`.
2. Re-reads `CLAuthorizationStatus` from `LocationsHandler.shared`.
3. Calls `nextStep(after:notificationStatus:criticalAlertSetting:locationStatus:)` (a pure function) to decide the next step.
4. Appends the result to `navigationPath`, or calls `dismiss()` when there is no further step.

### Navigation Logic (`nextStep`)

The routing is deterministic and depends on the current permission state:

| Current step | Condition | Next step |
|---|---|---|
| `nil` (start) | Notifications not yet determined | `.notifications` |
| `nil` (start) | Notifications known, location denied / restricted / not determined | `.location` |
| `nil` (start) | Notifications known, location authorised (whenInUse or always) | `.backgroundActivity` |
| `.notifications` | Location denied / restricted / not determined | `.location` |
| `.notifications` | Location authorised | `.backgroundActivity` |
| `.location` | Location authorised | `.backgroundActivity` |
| `.location` | Location still denied | `nil` (no background activity step) |
| `.backgroundActivity` | — | `.localNetwork` |
| `.localNetwork` | — | `.bluetooth` |
| `.bluetooth` | — | `.siri` |
| `.siri` | — | `nil` (dismiss) |

The notification and location steps are the only ones that are **conditionally skipped**; the remaining steps (background activity → local network → bluetooth → siri) are always shown in order.

## Steps

### Welcome Screen

Presented as the root of the `NavigationStack`. Lists the app's major capabilities with icons and short descriptions:

- Off-grid mesh communication
- Private mesh network creation
- Real-time location sharing
- Privacy (no personal data collected)
- Message notifications
- Bluetooth connectivity
- Local-network (Wi-Fi/TCP) connectivity
- Siri & CarPlay

The "Get started" button advances to the first applicable step.

### 1. Notifications

Requests `UNAuthorizationOptions`: `.alert`, `.badge`, `.sound`, `.criticalAlert`.

Explains two categories of notification:

| Category | Examples |
|---|---|
| Standard | Incoming channel and direct messages, new node discoveries, low battery alerts |
| Critical Alerts | Packets flagged as critical — these bypass the mute switch and Do Not Disturb |

Tapping "Configure notification permissions" triggers the OS permission prompt and then advances to the next step.

### 2. Location

Requests **"Always"** location permission via `LocationsHandler.shared.requestLocationAlwaysPermissions()`.

Why the app uses location:
- Sharing the phone's GPS position to the mesh instead of relying on node hardware GPS
- Distance measurements between the phone and other nodes
- Distance-based filtering of the node list and mesh map
- The blue "my location" dot in the mesh map

The step also presents a **"Enable Location Sharing"** toggle (`UserDefaults.provideLocation`) that the user can switch on immediately; enabling it also sets `provideLocationInterval = 30` seconds and `enableSmartPosition = true`.

The description text contains a tappable "settings" link that opens the app's iOS Settings page, allowing the user to change the permission later.

### 3. Background Activity

No OS permission dialog — this step only explains the feature and provides an opt-in toggle.

**"Enable Background Activity"** toggle (`LocationsHandler.shared.backgroundActivity`) controls whether the app requests the `always` location mode needed for background operation.

Benefits described:
- Continuous location updates while using other apps
- Background mesh tracking (receiving position updates from other nodes)

The user is reminded that enabling this may increase battery usage and that the setting can be changed at any time in the app settings.

### 4. Local Network Access

Requests local-network permission via `TCPTransport.requestLocalNetworkAuthorization()`.

Why the app uses the local network:
- Connecting to TCP-based Meshtastic nodes on the same Wi-Fi network
- Background local-network connections are **not** supported — the node may disconnect when the app is sent to the background

Minimum recommended firmware for TCP connections: **2.7.4**.

### 5. Bluetooth

Requests Bluetooth permission via `BluetoothAuthorizationHelper.requestBluetoothAuthorization()`.

Why the app uses Bluetooth:
- BLE-connected nodes provide the most reliable messaging experience
- BLE supports background connections — the app can remain connected while in the background

### 6. Siri, Shortcuts & CarPlay

Requests Siri/Intents permission via `INPreferences.requestSiriAuthorization(_:)`.

Supported voice commands:

| Intent | Example phrase |
|---|---|
| Send a group (channel) message | "Send a Meshtastic group message" |
| Send a direct message | "Send a Meshtastic direct message" |
| Shut down the connected node | "Shut down my Meshtastic node" |
| Restart the connected node | "Restart my Meshtastic node" |
| Disconnect from the BLE node | "Disconnect Meshtastic" |

CarPlay support lets users read and reply to channel and direct messages from the vehicle's display.

## State & UserDefaults

| Key | Type | Default | Description |
|---|---|---|---|
| `firstLaunch` | `Bool` | `true` | Set to `false` when the onboarding sheet is dismissed for the first time. |
| `showDeviceOnboarding` | `Bool` | `false` | Set to `true` to force the onboarding sheet to appear again at any time. Reset to `false` automatically by `ContentView.onChange`. |
| `provideLocation` | `Bool` | `false` | Toggled on the Location step. Enables periodic position sharing from the phone to the mesh. |
| `provideLocationInterval` | `Int` | `30` | Interval in seconds between position broadcasts when `provideLocation` is `true`. Set to 30 when the toggle is first enabled during onboarding. |

## Tests

Unit tests for the feature live in:

```
MeshtasticTests/DeviceOnboardingTests.swift
```

Three test suites use [Swift Testing](https://developer.apple.com/xcode/swift-testing/):

| Suite | What it covers |
|---|---|
| `DeviceOnboarding.SetupGuide` | All cases exist, enum is `Hashable`, equality is correct |
| `DeviceOnboarding string formatters` | Each `createXxxString()` helper produces text containing the expected keywords and a tappable "settings" link |
| `DeviceOnboarding navigation` | `nextStep(after:…)` produces the correct next step for all permission-state combinations |
