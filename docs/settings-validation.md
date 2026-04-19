# Meshtastic-Apple — Settings Validation Reference

This document describes every field presented in the **Config** and **Module Config** settings screens, the validation rules applied in the SwiftUI forms, and the underlying constraints from the protobuf definitions.

---

## Shared Components

The following reusable components are used across all config forms.

### `UpdateIntervalPicker` (`Views/Settings/UpdateIntervalPicker.swift`)

A reusable picker bound to an `UpdateInterval` value. Each usage specifies an `IntervalConfiguration` that restricts which time values appear. If the device's current value does not match a predefined option an orange ⚠️ warning is shown: *"The configured value: (X) is not one of the optimized options."* Manual/arbitrary values are accepted and transmitted but are flagged.

| Configuration | Allowed values (seconds) |
|---|---|
| `broadcastShort` | 0, 1800, 3600, 7200, 10800, 14400, 18000, 21600, 43200, 64800, 86400, 129600, 172800, 259200, never |
| `broadcastMedium` | 3600, 7200, 10800, 14400, 18000, 21600, 43200, 64800, 86400, 129600, 172800, 259200, never |
| `broadcastLong` | 10800, 14400, 18000, 21600, 43200, 64800, 86400, 129600, 172800, 259200, never |
| `detectionSensorMinimum` | 0, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 10800, 14400, 18000, 21600, 43200, 64800, 86400, 129600, 172800, 259200 |
| `detectionSensorState` | 0, 900, 1800, 3600, 7200, 10800, 14400, 18000, 21600, 43200, 64800, 86400, 129600, 172800, 259200 |
| `nagTimeout` | 0, 1, 5, 10, 15, 30, 60 |
| `paxCounter` | 900, 1800, 3600, 7200, 10800, 14400, 18000, 21600, 43200, 64800, 86400, 129600, 172800, 259200 |
| `rangeTestSender` | 0, 15, 30, 45, 60, 300, 600, 900, 1800, 3600 |
| `smartBroadcastMinimum` | 15, 30, 45, 60, 300, 600, 900, 1800, 3600 |

### `SecureInput` (`Views/Helpers/SecureInput.swift`)

A text field with a visibility-toggle button and an `isValid: Bool` binding. When `isValid` is `false` the field is decorated with a red `RoundedRectangle` stroke. Used for all cryptographic-key fields in Security Config.

### `FloatField` (local to `PowerConfig.swift`)

A generic float text field that accepts an `isValid: (Float) -> Bool` closure. On every change the closure is evaluated; if the new value is invalid the field reverts to the previous value.

---

## Config Screens

### 1. LoRa Config (`Config/LoRaConfig.swift`)

Protobuf message: `Config.LoRaConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `region` | Picker (enum) | Values from `RegionCode` enum (unset, US, EU_433, EU_868, CN, JP, ANZ, KR, TW, RU, IN, NZ_865, TH, LORA_24, UA_433, UA_868, MY_433, MY_919, SG_923) |
| `usePreset` | Toggle | Boolean |
| `modemPreset` | Picker (enum) | Values from `ModemPresets` enum; disabled when `usePreset` is false |
| `hopLimit` | Picker (`ForEach 0..<8`) | Integer **0–7** inclusive. Proto: *"Maximum number of hops. This can't be greater than 7."* |
| `txEnabled` | Toggle | Boolean |
| `txPower` | `Stepper(in: 1...30, step: 1)` | Integer **1–30 dBm**. Proto: *"If zero, then use default max legal continuous power."* (0 = default; UI starts at 1 to prevent accidental override) |
| `channelNum` | `TextField` (integer `NumberFormatter`, no grouping separator) | `UInt32`; disabled when `overrideFrequency > 0` |
| `bandwidth` | Picker (enum `BandwidthCodes`) | Enum-constrained |
| `spreadFactor` | Picker (`ForEach 7..<13`) | Integer **7–12**. Proto: *"A number from 7 to 12. Indicates number of chirps per symbol as 1<<spread_factor."* Value 0 maps internally to 12 |
| `codingRate` | Picker (`ForEach 5..<9`) | Integer **5–8**. Proto: *"The denominator of the coding rate. ie for 4/5, the value is 5."* Value 0 maps internally to 8 |
| `rxBoostedGain` | Toggle | Boolean |
| `overrideFrequency` | `TextField` (`NumberFormatter`, `maximumFractionDigits: 4`, no grouping separator) | `Float`; disables `channelNum` field when > 0 |
| `ignoreMqtt` | Toggle | Boolean |
| `okToMqtt` | Toggle | Boolean |

**Dirty-tracking:** All fields use `.onChange` comparing new value against `node?.loRaConfig?.field ?? -1`; `hasChanges` is set to `true` on any discrepancy.

---

### 2. Device Config (`Config/DeviceConfig.swift`)

Protobuf message: `Config.DeviceConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `deviceRole` | Picker (enum) | Values from `DeviceRoles` enum (client, clientMute, router, routerLate, repeater, tracker, sensor, tak, clientHidden, lostAndFound, takTracker). Selecting a router/routerLate/clientBase role triggers a confirmation dialog |
| `rebroadcastMode` | Picker (enum `RebroadcastModes`) | Enum-constrained |
| `nodeInfoBroadcastSecs` | `UpdateIntervalPicker(config: .broadcastLong)` | Predefined options ≥ 3 hours (10 800 s). On `setInitialValues`: if stored value < 10 800, it is **clamped to 10 800** |
| `doubleTapAsButtonPress` | Toggle | Boolean |
| `tripleClickAsAdHocPing` | Toggle | Boolean |
| `ledHeartbeatEnabled` | Toggle | Boolean |
| `tzdef` | `TextField` | **Max 63 UTF-8 bytes.** `.onChange` trims trailing characters until `utf8.count <= 63` |
| `buttonGPIO` | Picker (GPIO list 0–48) | Integer |
| `buzzerGPIO` | Picker (GPIO list 0–48) | Integer |

---

### 3. Display Config (`Config/DisplayConfig.swift`)

Protobuf message: `Config.DisplayConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `screenOnSeconds` | `UpdateIntervalPicker(config: .broadcastShort)` | Predefined interval options |
| `screenCarouselInterval` | Picker (enum `ScreenCarouselIntervals`) | Enum-constrained |
| `compassNorthTop` | Toggle | Boolean |
| `wakeOnTapOrMotion` | Toggle | Boolean |
| `flipScreen` | Toggle | Boolean |
| `oledType` | Picker (enum `OledTypes`) | Enum-constrained |
| `displayMode` | Picker (enum `DisplayModes`) | Enum-constrained |
| `units` | Picker (enum `Units`) | Enum-constrained (metric / imperial) |
| `use12HourClock` | Toggle | Boolean |
| `headingBold` | Toggle | Boolean |

All fields use standard `.onChange` dirty-tracking only; no custom range or byte-length validation.

---

### 4. Power Config (`Config/PowerConfig.swift`)

Protobuf message: `Config.PowerConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `isPowerSaving` | Toggle | Boolean; only shown for ESP32/ESP32S3 devices or specific roles |
| `shutdownOnPowerLoss` | Toggle | Boolean |
| `shutdownAfterSecs` | `UpdateIntervalPicker(config: .all)` | Any `FixedUpdateIntervals` value |
| `adcOverride` | Toggle | Boolean; enables the `adcMultiplier` field |
| `adcMultiplier` | `FloatField(isValid: { (2.0 ... 6.0).contains($0) })` | **Float 2.0–6.0 inclusive.** Invalid input is silently reverted to the previous value. When `adcOverride` is false the field is hidden and `0` is sent |
| `waitBluetoothSecs` | `UpdateIntervalPicker` | Predefined interval options |
| `lsSecs` | `UpdateIntervalPicker` | Predefined interval options |
| `minWakeSecs` | `UpdateIntervalPicker` | Predefined interval options |

---

### 5. Network Config (`Config/NetworkConfig.swift`)

Protobuf message: `Config.NetworkConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `wifiEnabled` | Toggle | Boolean; only shown on devices where `hasWifi == true` |
| `wifiSsid` | `TextField` | **Max 32 UTF-8 bytes.** `.onChange` trims trailing characters until `utf8.count <= 32` |
| `wifiPsk` | `TextField` (`.keyboardType(.asciiCapable)`) | **Max 63 UTF-8 bytes.** `.onChange` trims trailing characters until `utf8.count <= 63` |
| `ethEnabled` | Toggle | Boolean; only shown on devices where `hasEthernet == true` |
| `udpEnabled` | Toggle | Boolean |

---

### 6. Bluetooth Config (`Config/BluetoothConfig.swift`)

Protobuf message: `Config.BluetoothConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean |
| `mode` | Picker (enum `BluetoothModes`) | randomPin, fixedPin, noPin |
| `fixedPin` | `TextField` (`.keyboardType(.decimalPad)`) | **Exactly 6 digits, no leading zeros.** `.onChange`: (1) removes all `"0"` characters if the first character is `"0"`; (2) truncates to 6 characters with `.prefix(6)` if over-length; (3) sets `shortPin = true` and shows red error text *"BLE Pin must be 6 digits long."* if under-length. Only shown when `mode == .fixedPin` |

Proto field: `fixedPin: UInt32` — the app transmits the string converted to `UInt32`.

---

### 7. Security Config (`Config/SecurityConfig.swift`)

Protobuf message: `Config.SecurityConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `publicKey` | Read-only `Text` display | Auto-derived from `privateKey` (Curve25519); not editable |
| `privateKey` | `SecureInput(isValid: $hasValidPrivateKey)` | **32 bytes when decoded from Base64.** `.onChange`: decodes as Base64; if `Data.count == 32` → valid and the public key display is refreshed; otherwise invalid with red border |
| `adminKey` | `SecureInput(isValid: $hasValidAdminKey)` | **32 bytes when decoded from Base64, or empty.** Empty string → valid; `Data.count == 32` → valid; otherwise invalid with red border |
| `adminKey2` | `SecureInput(isValid: $hasValidAdminKey2)` | Same rule as `adminKey` |
| `adminKey3` | `SecureInput(isValid: $hasValidAdminKey3)` | Same rule as `adminKey` |
| `isManaged` | Toggle | Boolean |
| `serialEnabled` | Toggle | Boolean |
| `debugLogApiEnabled` | Toggle | Boolean |

**Save guard:** The save action includes a `guard hasValidPrivateKey && hasValidAdminKey && hasValidAdminKey2 && hasValidAdminKey3 else { return }` — a save is silently blocked if any key field is invalid.

---

### 8. Position Config (`Config/PositionConfig.swift`)

Protobuf message: `Config.PositionConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `smartPositionEnabled` | Toggle | Boolean; controls visibility of smart-position sub-fields |
| `deviceGpsEnabled` | Toggle | Boolean |
| `gpsMode` | Picker (enum `GpsModes`) | Enum-constrained |
| `fixedPosition` | Toggle | Requires firmware version check and shows a confirmation dialog |
| `positionBroadcastSeconds` | `UpdateIntervalPicker(config: .broadcastShort)` | Predefined options: 30 min–72 hours or never |
| `broadcastSmartMinimumDistance` | `TextField` (integer) | `UInt32`, no additional validation |
| `broadcastSmartMinimumIntervalSecs` | `UpdateIntervalPicker(config: .smartBroadcastMinimum)` | Predefined options: 15 s–1 hour |
| `gpsUpdateInterval` | Picker (enum `GpsUpdateIntervals`) | Enum-constrained |
| `positionFlags` (bitfield) | Multiple Toggles | Each toggle controls one bit (altitude, speed, heading, satellite count, sequence number, timestamp, heading, name). Combined into a single `UInt32` on save |

---

## Module Config Screens

### 1. MQTT Config (`Config/Module/MQTTConfig.swift`)

Protobuf message: `ModuleConfig.MQTTConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean |
| `proxyToClientEnabled` | Toggle | Boolean |
| `address` | `TextField` | **Max 62 UTF-8 bytes.** `.onChange` trims trailing characters |
| `username` | `TextField` | **Max 62 UTF-8 bytes.** `.onChange` trims trailing characters |
| `password` | `TextField` | **Max 30 UTF-8 bytes.** `.onChange` trims trailing characters |
| `root` | `TextField` | **Max 30 UTF-8 bytes.** `.onChange` trims trailing characters. Proto default: `"msh"` |
| `encryptionEnabled` | Toggle | Boolean |
| `jsonEnabled` | Toggle | Boolean |
| `tlsEnabled` | Toggle | Boolean |
| `mapReportingEnabled` | Toggle | Boolean; requires a consent toggle before it can be enabled |
| `mapPublishIntervalSecs` | `UpdateIntervalPicker(config: .broadcastMedium)` | Predefined options: 1–72 hours |
| `mapPositionPrecision` | `Slider(in: 12...15, step: 1)` | Integer **12–15** inclusive |

**Duty cycle warning:** If the connected node's duty cycle is between 0 and 100 (exclusive), an orange warning about duty cycle restrictions is shown.

---

### 2. Telemetry Config (`Config/Module/TelemetryConfig.swift`)

Protobuf message: `ModuleConfig.TelemetryConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `deviceUpdateInterval` | `UpdateIntervalPicker(config: .broadcastShort)` | Predefined options: 30 min–72 hours |
| `deviceTelemetryEnabled` | Toggle | Boolean; only shown on firmware ≥ 2.7.12 |
| `environmentUpdateInterval` | `UpdateIntervalPicker(config: .broadcastShort)` | Predefined options: 30 min–72 hours |
| `environmentMeasurementEnabled` | Toggle | Boolean |
| `environmentScreenEnabled` | Toggle | Boolean |
| `environmentDisplayFahrenheit` | Toggle | Boolean |
| `powerMeasurementEnabled` | Toggle | Boolean |
| `powerUpdateInterval` | `UpdateIntervalPicker(config: .broadcastShort)` | Predefined options: 30 min–72 hours |
| `powerScreenEnabled` | Toggle | Boolean |

No range or byte-length validation beyond the predefined picker options.

---

### 3. Canned Messages Config (`Config/Module/CannedMessagesConfig.swift`)

Protobuf message: `ModuleConfig.CannedMessageConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean |
| `sendBell` | Toggle | Boolean |
| `rotary1Enabled` | Toggle | Boolean; **mutually exclusive** with `updown1Enabled` (the other is disabled while this is on) |
| `updown1Enabled` | Toggle | Boolean; **mutually exclusive** with `rotary1Enabled` |
| `inputbrokerPinA` | Picker (GPIO list) | Integer |
| `inputbrokerPinB` | Picker (GPIO list) | Integer |
| `inputbrokerPinPress` | Picker (GPIO list) | Integer |
| `inputbrokerEventCw` | Picker (enum `InputEventSets`) | Enum-constrained |
| `inputbrokerEventCcw` | Picker (enum `InputEventSets`) | Enum-constrained |
| `inputbrokerEventPress` | Picker (enum `InputEventSets`) | Enum-constrained |
| `messages` | `TextField` (multiline) | **Max 198 UTF-8 bytes.** `.onChange` trims trailing characters until `utf8.count <= 198` |

---

### 4. Detection Sensor Config (`Config/Module/DetectionSensorConfig.swift`)

Protobuf message: `ModuleConfig.DetectionSensorConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean |
| `role` | Segmented Picker (sensor / client) | Stored in `AppStorage`; controls which sub-form sections are visible |
| `sendBell` | Toggle | Boolean; sensor role only |
| `name` | `TextField` | **Max 20 UTF-8 bytes.** `.onChange` trims trailing characters |
| `triggerType` | Picker (enum) | Enum-constrained |
| `usePullup` | Toggle | Boolean |
| `minimumBroadcastSecs` | `UpdateIntervalPicker(config: .detectionSensorMinimum)` | Predefined options: 0–72 hours |
| `stateBroadcastSecs` | `UpdateIntervalPicker(config: .detectionSensorState)` | Predefined options: 0–72 hours |
| `monitorPin` | Picker (GPIO list) | Integer |

---

### 5. External Notification Config (`Config/Module/ExternalNotificationConfig.swift`)

Protobuf message: `ModuleConfig.ExternalNotificationConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean |
| `alertBell` | Toggle | Boolean |
| `alertBellBuzzer` | Toggle | Boolean |
| `alertBellVibra` | Toggle | Boolean |
| `alertMessage` | Toggle | Boolean |
| `alertMessageBuzzer` | Toggle | Boolean |
| `alertMessageVibra` | Toggle | Boolean |
| `active` | Toggle | Boolean (active-high vs active-low) |
| `output` | Picker (GPIO list 0–49) | Integer (`UInt32`) |
| `outputBuzzer` | Picker (GPIO list) | Integer |
| `outputVibra` | Picker (GPIO list) | Integer |
| `outputMilliseconds` | Picker (`OutputIntervals` enum) | Values (ms): 0, 1000, 2000, 3000, 4000, 5000, 10000, 15000, 30000, 60000 |
| `nagTimeout` | `UpdateIntervalPicker(config: .nagTimeout)` | Predefined options: 0, 1, 5, 10, 15, 30, 60 seconds |
| `usePWM` | Toggle | Boolean |
| `useI2SAsBuzzer` | Toggle | Boolean |

No string-length or numeric-range validation beyond the predefined picker options.

---

### 6. Store and Forward Config (`Config/Module/StoreForwardConfig.swift`)

Protobuf message: `ModuleConfig.StoreAndForwardConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean |
| `isServer` | Toggle | Boolean |
| `heartbeat` | Toggle | Boolean |
| `records` | Picker | Values: 0, 25, 50, 75, 100 |
| `historyReturnMax` | Picker | Values: 0, 25, 50, 75, 100 |
| `historyReturnWindow` | Picker | Values (seconds): 0, 60, 300, 600, 900, 1800, 3600, 7200 |

All options are predefined; no custom validation.

---

### 7. Serial Config (`Config/Module/SerialConfig.swift`)

Protobuf message: `ModuleConfig.SerialConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean |
| `echo` | Toggle | Boolean |
| `rxd` | Picker (GPIO list 0–49) | Integer |
| `txd` | Picker (GPIO list 0–49) | Integer |
| `baudRate` | Picker (enum `SerialBaudRates`) | Enum-constrained standard baud rates |
| `timeout` | Picker | Predefined timeout values |
| `overrideConsoleSerialPort` | Toggle | Boolean |
| `mode` | Picker (enum `SerialModes`) | Enum-constrained (default, simple, proto, textmsg, nmea, caltopo) |

---

### 8. Range Test Config (`Config/Module/RangeTestConfig.swift`)

Protobuf message: `ModuleConfig.RangeTestConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean |
| `sender` | `UpdateIntervalPicker(config: .rangeTestSender)` | Predefined options: 0, 15, 30, 45, 60, 300, 600, 900, 1800, 3600 seconds |
| `save` | Toggle | Boolean |

---

### 9. RTTTL Config (`Config/Module/RtttlConfig.swift`)

Protobuf: transmitted as a plain string via `saveRtttlConfig`.

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `ringtone` | `TextField` | **Max 228 UTF-8 bytes.** `.onChange` trims trailing characters until `utf8.count <= 228`. Value is stripped of leading/trailing whitespace before being sent |

---

### 10. Ambient Lighting Config (`Config/Module/AmbientLightingConfig.swift`)

Protobuf message: `ModuleConfig.AmbientLightingConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `ledState` | Toggle | Boolean |
| `current` | `Stepper(in: 0...31, step: 1)` | Integer **0–31** (LED current level) |
| `color` | `ColorPicker` | SwiftUI color picker; converted to RGB `UInt32` on save |

---

### 11. TAK Module Config (`Config/Module/TAKModuleConfig.swift`)

Protobuf message: `ModuleConfig.TAKConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean; entire form only shown for roles with TAK access (`tak`, `takTracker`) |
| `team` | Picker (enum `TakTeams`) | Enum-constrained (cyan, white, yellow, orange, magenta, red, maroon, purple, dark blue, blue, green, dark green, brown, …) |
| `role` | Picker (enum `TakRoles`) | Enum-constrained (team member, team lead, HQ, sniper, medic, RTO, FO, casevac, transport, ground, air, control, Blue Force, EOD, intelligence, recon, belligerent, sus, exercise participant) |

---

### 12. Pax Counter Config (`Config/Module/PaxCounterConfig.swift`)

Protobuf message: `ModuleConfig.PaxcounterConfig`

| Field | UI Control | Constraint / Validation |
|---|---|---|
| `enabled` | Toggle | Boolean |
| `paxcounterUpdateInterval` | `UpdateIntervalPicker(config: .paxCounter)` | Predefined options: 15 min–72 hours |

---

## Validation Patterns Summary

| Pattern | Where Used | Details |
|---|---|---|
| **UTF-8 byte truncation** | All string `TextField` fields | `.onChange` loop: `while utf8.count > limit { dropLast() }` |
| **Numeric stepper range** | `txPower` (1–30), `current` (0–31) | Enforced by SwiftUI `Stepper(in:)` |
| **Enum picker** | All categorical fields | Statically typed; only valid enum cases selectable |
| **Predefined interval picker** | All timing fields | `UpdateIntervalPicker` with `IntervalConfiguration`; out-of-range values shown with ⚠️ warning |
| **Slider range** | `mapPositionPrecision` | `Slider(in: 12...15, step: 1)` |
| **Float closure validation** | `adcMultiplier` | `FloatField(isValid:)` reverts to previous value on invalid input |
| **Base64 + byte-count key validation** | `privateKey`, `adminKey` ×3 | `Data(base64Encoded:)?.count == 32`; `SecureInput` shows red border when `isValid == false` |
| **Guard-on-save** | Security Config | Save is blocked until all four key fields are valid |
| **PIN digit enforcement** | `fixedPin` (Bluetooth) | Leading-zero removal; `.prefix(6)` truncation; `shortPin` flag triggers red error text |
| **Minimum value clamp on load** | `nodeInfoBroadcastSecs` | Stored value < 10 800 s is clamped to 10 800 s when the view initialises |
| **Conditional field visibility** | Many screens | Fields hidden/disabled based on device capabilities (`hasWifi`, `hasEthernet`), firmware version (`checkIsVersionSupported`), device role, or toggle state |
| **Mutual exclusion** | `rotary1Enabled` / `updown1Enabled` | Each disables the other's toggle |
| **Confirmation dialog on change** | Device Config `deviceRole`, Position Config `fixedPosition` | Destructive/special roles require user confirmation |
| **Dirty-tracking (`hasChanges`)** | All screens | `@State var hasChanges = false` set via `.onChange` comparing new value against `node?.config?.field ?? -1`; controls `SaveConfigButton` enabled state |

---

## String Field Byte Limits at a Glance

| Field | Screen | Max UTF-8 Bytes |
|---|---|---|
| `wifiSsid` | Network Config | 32 |
| `wifiPsk` | Network Config | 63 |
| `tzdef` | Device Config | 63 |
| `address` (MQTT) | MQTT Config | 62 |
| `username` (MQTT) | MQTT Config | 62 |
| `root` (MQTT topic) | MQTT Config | 30 |
| `password` (MQTT) | MQTT Config | 30 |
| `messages` (canned) | Canned Messages Config | 198 |
| `name` (detection sensor) | Detection Sensor Config | 20 |
| `ringtone` (RTTTL) | RTTTL Config | 228 |
