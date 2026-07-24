---
title: Transport Layer
parent: Developer Guide
nav_order: 4
---

# Transport Layer

`AccessoryManager` abstracts BLE, TCP/IP, and serial transports behind a single interface. Views and services interact only with `AccessoryManager` — never with transport implementations directly.

## Transport Implementations

Transports live in `Meshtastic/Accessory/Transports/`:

| File | Protocol | Notes |
|------|----------|-------|
| `BLETransport.swift` | CoreBluetooth | Standard BLE connection to radios |
| `TCPTransport.swift` | Network.framework | Wi-Fi / TCP/IP to radios with networking |
| `SerialTransport.swift` | IOKit serial | macOS only; USB-serial adapters |

Each transport conforms to a `MeshTransport` protocol that exposes `connect()`, `disconnect()`, `send(data:)`, and a `received` publisher.

### BLETransport Status on Bluetooth State Changes

`BLETransport.status` mirrors `CBManagerState` via `handleCentralState(_:central:)`. `.poweredOn` settles on `.discovering`, not `.ready` — `.ready` is only assigned later, by `stopScanning()`, and only while Bluetooth is still powered on. Every other state — including `.poweredOff` — settles on `.error(...)`. Concretely, when Bluetooth powers off, `status` becomes `.error(BLETransport.poweredOffStatusMessage)` ("Bluetooth is powered off") and stays there. This matches `.unauthorized`, `.unsupported`, `.resetting`, and `.unknown`, which all settle on `.error(...)` too.

`status` is actor-isolated state, so nothing outside `BLETransport` could observe it changing until `statusUpdates() -> AsyncStream<TransportStatus>` was added: it replays the current status to a new subscriber, then yields again on every subsequent change (a `didSet` on `status` drives the broadcast, guarded so an unchanged value never yields a duplicate). `AccessoryManager.observeBLETransportStatus()` is the sole subscriber — it consumes the stream for the app's lifetime and mirrors every value onto `@Published var bleTransportStatus`, from which the computed `isBluetoothPoweredOff` derives. The Connect tab reads `isBluetoothPoweredOff` to show an inline "Bluetooth is off" row in Available Radios, since the system "Bluetooth is turned off" alert is intentionally suppressed (`CBCentralManagerOptionShowPowerAlertKey: false`, see above) and would otherwise be the only in-app signal a BLE user gets.

## AccessoryManager Extension Map

| Extension | Key Methods |
|-----------|------------|
| `+Discovery` | `startScanning()`, `stopScanning()`, `peripheral(_:didDiscover:)` |
| `+Connect` | `connect(peripheral:)`, `disconnect()`, `centralManager(_:didConnect:)` |
| `+ToRadio` | `sendPacket(_:)`, `sendWantConfig()`, `sendWaypoint(_:)` |
| `+FromRadio` | `handleFromRadio(_:)`, `handleMeshPacket(_:)` |
| `+Position` | `startLocationUpdates()`, `sendPosition(_:)` |
| `+MQTT` | `connectMQTT()`, `publishPacket(_:)`, `mqttClient(_:didReceiveMessage:)` |
| `+TAK` | `handleATAKPluginPacket(_:)`, `handleATAKPluginV2Packet(_:)`, `handleATAKForwarderPacket(_:)`, `sendTAKPacket(_:channel:)`, `sendTAKV2Packet(_:channel:)`, `sendCoTToMeshV2(_:channel:)`. See [TAK Protocol](tak-protocol.html) for the V1/V2 wire format detail. |

## Packet Flow (Inbound)

```
Radio (BLE/TCP/Serial)
  → Transport.received publisher
  → AccessoryManager+FromRadio.handleFromRadio(_:)
  → Decode protobuf (MeshtasticProtobufs)
  → Route by packet type:
      MeshPacket  → handleMeshPacket(_:)
      NodeInfo    → updateNodeInfo(_:)
      MyNodeInfo  → updateMyNodeInfo(_:)
      Config      → updateConfig(_:)
      ...
  → Write to SwiftData via MeshPackets @ModelActor
  → Publish changes via @Published properties (UI updates)
```

## Frame Decoding & Encoding Validation

Every transport turns raw inbound bytes into a `FromRadio` frame through one shared funnel, `FromRadioDecoder.classify(_:)` in `Accessory/Protocols/Connection.swift`, so BLE, TCP, and Serial handle a malformed frame identically instead of each rolling its own `try? FromRadio(serializedBytes:)`. It returns a `FromRadioDecodeOutcome`:

| Outcome | Meaning | Transport action |
|---------|---------|------------------|
| `.decoded(FromRadio)` | Frame decoded cleanly | Yield `.data(_)` to `AccessoryManager` |
| `.skipInvalidUTF8(Error)` | A string field (e.g. a node's `long_name`) failed SwiftProtobuf's UTF-8 validation | Log and **skip the frame**; the connection stays alive and keeps reading |
| `.failed(Error)` | Genuine framing / wire corruption | BLE & TCP call `disconnect(withError:shouldReconnect:)` and reconnect; Serial logs and skips |

An invalid encoding in a single string field is a per-field content problem, not a transport failure, so it must not tear down an otherwise healthy stream. SwiftProtobuf validates UTF-8 during decode and throws `BinaryDecodingError.invalidUTF8`; `FromRadioDecoder` isolates that case so only genuine framing errors trigger a reconnect.

## Packet Flow (Outbound)

```
View / Service
  → AccessoryManager+ToRadio.sendPacket(_:)
  → Encode to protobuf (ToRadio wrapper)
  → Transport.send(data:)
  → Radio
```

## Connection Sequencing

`AccessoryManager+Connect` runs connection setup as a sequenced series of steps: transport connect, heartbeat, `wantConfig`, optional database retrieval, and version checks.

During an explicit radio switch from the Connect view, the app uses the same connect pipeline but enables an extra post-config refresh. Once `sendWantConfig()` completes for the newly selected device, the app first applies the bundled `DeviceHardware.json` catalog and bundled device images to SwiftData, then schedules `MeshtasticAPI.shared.refreshDevicesAPIData()` in the background. That network refresh updates the same locally cached hardware catalog from `https://api.meshtastic.org/resource/deviceHardware` without blocking the rest of the connection sequence.

This refresh is only enabled for the switch-radio flow. Automatic reconnects and ordinary connects continue using the standard transport handshake without forcing a hardware catalog refresh.

### BLE Pairing PIN Handshake

A first-ever connection to an encrypted radio makes iOS present a 6-digit pairing PIN sheet. `BLEConnection` gates connect-completion on that bond so the sheet is not torn down before the user can respond:

- **Notification-gated handshake.** After the required characteristics are discovered, `BLEConnection` does *not* resolve the connect step immediately. It subscribes to the `FROMNUM` notify characteristic (always notify-capable and encrypted) and holds the connect continuation open until `didUpdateNotificationState` confirms the subscription. On a first-ever connection that CoreBluetooth callback does not fire until the user dismisses the pairing sheet, so the connection stays alive while the PIN is entered.
- **Pairing timeout.** `AccessoryManager+Connect` selects the Step 1 timeout based on whether the peripheral is already bonded: a first-time BLE bond gets a long window (90s) so there is time to read and type the PIN, while already-bonded peripherals and non-BLE transports keep the fast reconnect timeout (5s) so a dead/out-of-range radio still fails quickly.
- **Pairing-failure classification.** A wrong or cancelled PIN surfaces as a `CBATTError` (insufficient authentication/encryption/authorization) or a `CBError` (`encryptionTimedOut`, `peerRemovedPairingInformation`). `BLEConnection.isPairingFailure(_:)` distinguishes these bond failures from benign per-characteristic errors (e.g. "notify not supported") so only real failures fail the connect. Cancelling the sheet often arrives as a plain peripheral disconnect, so `disconnect` also resumes any suspended connect continuation to fail Step 1 fast instead of waiting out the full window.
- **Paired-hint lifecycle.** The set of bonded peripheral UUIDs is persisted in `UserDefaults.pairedPeripheralIds`. A confirmed subscription calls `rememberPairedPeripheral`; a bond failure or a teardown while still awaiting confirmation calls `forgetPairedPeripheral`, so a bond the user removes in iOS Settings self-heals back to the long pairing window on the next attempt. The legacy `preferredPeripheralId` is migrated into this list exactly once (guarded by `migratedPreferredPeripheralPairing`) so upgrading users skip the long window on their first reconnect without permanently pinning the fast timeout.

## Adding a New Packet Type

1. Add the protobuf definition in the `protobufs/` submodule.
2. Run `./scripts/gen_protos.sh`.
3. Add a decode/dispatch case in `AccessoryManager+FromRadio.handleFromRadio(_:)`.
4. Add a send method in `AccessoryManager+ToRadio.swift`.
5. Add a model property or SwiftData entity if the data needs to persist.
6. Write unit tests against the encode/decode round-trip.

## Concurrency Notes

`AccessoryManager` is not `@MainActor`. Its `@Published` properties are observed from SwiftUI views on the main actor. Use `await MainActor.run { }` when updating published properties from background tasks or CoreBluetooth delegate callbacks.

Background persistence writes must go through the `MeshPackets` `@ModelActor`, not the main `ModelContext`.
