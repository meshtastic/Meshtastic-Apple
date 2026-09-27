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

### BLE Writes When the Radio Is Out of Buffers

All of this applies only to `.withResponse` writes. `send` picks the write type from the characteristic's properties, preferring `.withoutResponse` when the radio advertises it, and CoreBluetooth does not call `didWriteValueFor` for that type — `performWrite` resumes its continuation as soon as the value is handed to CoreBluetooth, so no ATT error can come back and there is nothing to retry. Radios that refuse writes this way advertise plain `write`, which is how the path below is reachable at all. A `.withoutResponse` radio running out of buffers is invisible to the app; that backpressure is not handled.

`CBATTError.insufficientResources` on a `.withResponse` `TORADIO` write means the peripheral could not allocate for *that one write*. The link is healthy and the next write usually succeeds, so it is handled like an invalid UTF-8 field above — a per-item failure that must not tear down the stream — rather than like genuine wire corruption. It shows up on larger admin messages (`set_owner`, config sets) while 8-33 byte writes on the same connection go through; it was observed on a Heltec V4 (ESP32-S3/NimBLE) refusing a 104 byte write with an ATT MTU of 255 negotiated, so it is buffer exhaustion, not the size limit.

Two places cooperate on that:

- **`didWriteValueFor` does not escalate it.** Every other write error is passed to `handlePeripheralError`, which ends the session. For this one code the delegate resumes the waiting continuation with the error and returns, leaving the link up so `send` can retry. Escalating there would abort whatever operation was in flight — a single refused write used to end an entire config import.
- **`send` retries it, then escalates.** `BLEConnection.send` makes up to `writeAttemptLimit` (4) attempts — the initial write plus three retries, backing off 120/240/360ms. Once those are spent the failure is no longer momentary, so `send` calls `handlePeripheralError` itself (whose `.insufficientResources` case marks the connection **reconnecting**, not dead) and then propagates the original error to the caller. That call is the only path to that branch, since the delegate deliberately bypasses it.

The retry loop observes cancellation at defined points: `Task.checkCancellation()` before each attempt, `Task.sleep(for:)` throwing during the backoff, and one more check before escalating an exhausted final attempt. A cancellation request that lands between a check and the write it guards does not interrupt that write — it stops the *next* attempt or the escalation, whichever the loop reaches first. The effect is that a cancelled send stops issuing new writes and an intentional cancellation never starts a reconnect.

Write-with-response continuations live in `WriteContinuationStore`, keyed by UUID. The CoreBluetooth callback consumes the oldest entry (CoreBluetooth delivers `didWriteValueFor` in write order), while task cancellation resumes its specific UUID's continuation but leaves the entry in place as an ordered tombstone. The callback for the cancelled write later consumes that tombstone and no-ops, so it can never be misattributed to a newer write registered after the cancellation — such as the shielded `commit_edit_settings` send. All access is actor-isolated, and disconnect drains every remaining entry with an error. Writes without response are handed to CoreBluetooth and return immediately because CoreBluetooth provides no completion callback to cancel.

Every `ToRadio` write also logs its payload size against `maximumWriteValueLength(for:)`. An over-limit payload and an out-of-buffers radio both surface at the peripheral as the same opaque "resources are insufficient", and nothing recorded which one it was. These lines are `.error`, not `.debug`/`.info`, deliberately: only notice-and-above are persisted to `OSLogStore`, which is what the in-app log viewer reads, so a `.debug` line here would be invisible in the field.

## Connection Sequencing

`AccessoryManager+Connect` runs connection setup as a sequenced series of steps: transport connect, heartbeat, `wantConfig`, optional database retrieval, and version checks.

During an explicit radio switch from the Connect view, the app uses the same connect pipeline but enables an extra post-config refresh. Once `sendWantConfig()` completes for the newly selected device, the app first applies the bundled `DeviceHardware.json` catalog and bundled device images to SwiftData, then schedules `MeshtasticAPI.shared.refreshDevicesAPIData()` in the background. That network refresh updates the same locally cached hardware catalog from `https://api.meshtastic.org/resource/deviceHardware` without blocking the rest of the connection sequence.

This refresh is only enabled for the switch-radio flow. Automatic reconnects and ordinary connects continue using the standard transport handshake without forcing a hardware catalog refresh.

### Several Radios at Once

Up to `AccessoryManager.maxConnectedRadios` (4) radios can be connected, and every one runs the connect sequence above (`connect(to:)`, on its own `RadioSession`). The **focused** radio is `activeConnection`; the others are in `AccessoryManager.additionalRadios`, connected with `connectAdditionalRadio` (`connect(to:asFocused: false)`). A `ConnectAttempt` holds each connect's session, status and stepper.

- **Events.** `didReceive(_:from:)` routes another radio's events to `didReceiveAdditional`: its data goes through the same `processFromRadio(_:session:)` as the focused radio's, and its errors and disconnects end only that radio (its connect retries or gives up, or a connected radio is disconnected and reconnected later). Sessions of disconnected radios are remembered (`retiredAdditionalSessionIDs`) and their late events are dropped.
- **What stays the focused radio's.** The app-wide work in the steps and handlers: `activeConnection` and the preferred radio, the stored firmware version and update gate, the hardware catalog and image refresh, the Messages snapshot, the update notice, stopping discovery, the stale-node prune, the phone position loop, the remembered radios, the event firmware notification defaults, the TAK bridge, the Datadog radio context, `lastConfigRefresh`, and the lock-down coordinator. Admin requests a handler makes (timezone, canned messages, ringtone) are addressed to the radio they're for and go over its own connection.
- **Heartbeats** use the same timers on each radio's session, including the response timeout that closes a silent link.
- **One handshake at a time.** `HandshakeGate` serialises config and node-DB downloads across every radio; the ingest-actor recycle waits for it too. The recycle counts every radio's packets, and the retired actor keeps saving writes still in flight.
- **MQTT.** Every radio with "proxy to client" on gets its own `RadioMqttClient` (`AccessoryManager+RadioMQTT.swift`, on its session): its own `MqttClientProxyManager` instance, broker client and forward gate, built from its MQTT config and channels in connect Step 8 and stopped when the radio is torn down. The MQTT icon shows the focused radio's (`mqttProxyConnected`, `mqttTopics`); the MQTT settings and the channel editor act on the radio they configure (`startMqtt(forRadio:)`). Range test handling reads the receiving radio's own config (`RadioSession.wantRangeTestPackets`). Packet handling (stat and payload-less drops, hop-limit clamp, uplink payload) is shared with the focused radio in `MqttProxyPackets`.
- **Lock-down and firmware** (`AccessoryManager+RadioAttention.swift`). Every radio stays connected when it's locked or on old firmware. `LockdownCoordinator`, its passphrase sheet and the update gate are the focused radio's. A radio that isn't focused gets the passphrase saved for its peripheral, once; with none that works, or firmware below `minimumVersion` (checked in Step 6), it gets a `RadioAttention` and ContentView asks about it by name (`radioAttentionPrompt`). **Unlock** or **Update** focuses it without reconnecting (`focusRadioNeedingAttention`; a radio still connecting takes the focus when its connect finishes), which replays its last lock-down status into the coordinator (`RadioSession.lastLockdownStatus`) or raises the update gate. After an unlock its connect carries on (a connected radio gets its config again).
- **Reconnect and remembered radios.** A dropped additional radio goes through `scheduleAdditionalRadioReconnect` (bounded attempts, backing off to a minute). Radios connected alongside are remembered (`MyInfoEntity.autoConnect`) and brought back after the focused radio connects; a user's Disconnect forgets them. `device(for:)` also looks in `recentlyDiscoveredDevices`, which `stopDiscovery()` leaves alone, and a remembered radio that isn't found is kept in `awaitedRememberedRadios` until discovery sees it. `AccessoryManager+FocusHandover.swift` hands the focus to another radio when the focused one drops, then keeps trying the dropped radio as an additional one; the phone-position loop restarts with the new focus.
- **The preferred radio** is `PreferredRadio`: the radio reconnected at launch and restored in the background, which is the focused radio whenever one is connected. SwiftLint's `preferred_radio_defaults` rule keeps `UserDefaults.preferredPeripheralId/Num` inside it. Code about the radio it's working with uses that radio's `RadioSession`, or `activeDeviceNum` for the focused one.
- **Sending through a radio.** `connectedSession(forRadio:)` and `send(_:via:)` send on any connected radio's own connection; `sendMessage`, `sendPosition` and `addContactFromURL` take `viaRadio`, and `sendLocalAdmin` addresses admin messages to one of the user's radios through that radio.
- **BLE.** `BLETransport` keeps its connect continuations and active connections per peripheral identifier, so every CoreBluetooth callback reaches the right radio. The same peripheral still can't connect twice.
- **Switching** the focused radio (`switchToDevice`) disconnects it and connects the chosen radio. It no longer backs up, clears and restores the store, which every connected radio shares. A radio the store hasn't seen joins it; only a radio reporting a new node number for a known `deviceId` renumbers the store (`renumberIfSameRadio`).

BLE state restoration brings back every restored radio (`BLETransport.handleWillRestoreState`, T062/T155). Remote admin goes through the radio it's addressed from (`adminRoute(for:)`). TAK, CarPlay & Siri and the Watch use the radio chosen for them in App Settings (`session(for:)`, T102–T105), the focused one by default; the TAK settings screen edits that radio's identity and lists its channels (T161).

### BLE Pairing PIN Handshake

A first-ever connection to an encrypted radio makes iOS present a 6-digit pairing PIN sheet. `BLEConnection` gates connect-completion on that bond so the sheet is not torn down before the user can respond:

- **Notification-gated handshake.** After the required characteristics are discovered, `BLEConnection` does *not* resolve the connect step immediately. It subscribes to the `FROMNUM` notify characteristic (always notify-capable and encrypted) and holds the connect continuation open until `didUpdateNotificationState` confirms the subscription. On a first-ever connection that CoreBluetooth callback does not fire until the user dismisses the pairing sheet, so the connection stays alive while the PIN is entered.
- **Pairing timeout.** `AccessoryManager+Connect` selects the Step 1 timeout based on whether the peripheral is already bonded: a first-time BLE bond gets a long window (90s) so there is time to read and type the PIN, while already-bonded peripherals and non-BLE transports keep the fast reconnect timeout (5s) so a dead/out-of-range radio still fails quickly.
- **Pairing-failure classification.** A wrong or cancelled PIN surfaces as a `CBATTError` (insufficient authentication/encryption/authorization) or a `CBError` (`encryptionTimedOut`, `peerRemovedPairingInformation`). `BLEConnection.isPairingFailure(_:)` distinguishes these bond failures from benign per-characteristic errors (e.g. "notify not supported") so only real failures fail the connect. Cancelling the sheet often arrives as a plain peripheral disconnect, so `disconnect` also resumes any suspended connect continuation to fail Step 1 fast instead of waiting out the full window.
- **Paired-hint lifecycle.** The set of bonded peripheral UUIDs is persisted in `UserDefaults.pairedPeripheralIds`. A confirmed subscription calls `rememberPairedPeripheral`; a bond failure or a teardown while still awaiting confirmation calls `forgetPairedPeripheral`, so a bond the user removes in iOS Settings self-heals back to the long pairing window on the next attempt. The legacy `preferredPeripheralId` is migrated into this list exactly once (guarded by `migratedPreferredPeripheralPairing`) so upgrading users skip the long window on their first reconnect without permanently pinning the fast timeout.

### TCP Connect and Send Continuation Safety

`TCPConnection` bridges `NWConnection`'s callback API to `async`/`await` with checked continuations, and callbacks fire on the private `tcp.connection` queue while the continuation resumes on the actor. Two rules follow from that split:

- **The connect-time `stateUpdateHandler` must be one-shot.** It resumes the connect continuation from `.ready`, `.failed`, and `.cancelled`, and it stays installed until the awaiting task resumes on the actor and reaches the replacement handler. A second terminal state arriving inside that window would resume the same continuation twice, which is an uncatchable `SWIFT TASK CONTINUATION MISUSE` trap rather than a throwable error. Two paths reach it in practice: `.ready` followed by the Step 1 timeout or a user disconnect cancelling the step (`onCancel` calls `cancel()`, producing `.cancelled`), and `.ready` followed by the radio resetting the socket (`.failed`), which is what a radio that already has a TCP client does. A latch claimed inside the handler guarantees exactly one resume; because the handler only ever runs on the serial `tcp.connection` queue, a plain flag is sufficient synchronization.
- **The one-shot handler must not detach itself.** Nil-ing `stateUpdateHandler` from inside the handler after resuming looks like tidy cleanup but races the replacement handler: the nil store runs on `tcp.connection` while the task that resume just woke is concurrently installing the replacement on the actor, and nothing orders the two. If the nil lands last it erases the replacement, silently disabling the post-ready `.failed` teardown and its auto-reconnect, and it is an unsynchronized write to the same ARC-managed property from two threads. Installing the replacement *is* the detach; the latch alone carries the single-resume guarantee, including on the throw path where `connect()` rethrows and never installs a replacement.
- **`send` and `receiveData` must fail when there is no socket.** `disconnect()` sets `connection = nil`. Optional-chaining the `NWConnection` call inside a continuation body turns the whole statement into a no-op there: the continuation is created, never handed to a completion handler, and never resumed, so the caller suspends permanently. Both continuation bodies therefore `guard let` the connection and resume with `AccessoryError.disconnected` when it is gone. This matters because `AccessoryManager.send` checks `isConnected` and then calls `connection.send` across two separate suspension points, so a teardown can land between the check and the call, and the two heartbeat connect steps that call `send` (Steps 2 and 4) are constructed with `timeout: nil`, so nothing times the parked step out. Steps 3 and 5 (`sendWantConfig`, `sendWantDatabase`) do carry explicit timeouts, but the ~25 `send` call sites outside the connect sequence have no timeout wrapper at all.
- **An in-flight `send` is cancellation-aware without closing the socket.** Each `send` registers its checked continuation in a `WriteContinuationStore` under a unique ID and wraps the wait in `withTaskCancellationHandler`. The `NWConnection` completion and the cancellation handler race to remove that specific entry; whichever side removes it first resumes it and the other sees nil and no-ops, so a stale completion from a cancelled send can never resume a continuation registered later — such as the shielded `commit_edit_settings` send. Cancellation resumes with `CancellationError` but deliberately leaves the `NWConnection` alive, because a cancelled configuration import still needs the same connection to send its commit. The operating system may already have accepted the payload, so this is abandon-and-move-on behavior rather than a guarantee that no bytes reach the radio.

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
