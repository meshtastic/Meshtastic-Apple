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
