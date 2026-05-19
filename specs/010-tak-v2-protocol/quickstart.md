# Quickstart: TAK v2 Protocol Integration (Apple)

Developer onboarding for the Apple TAK v2 surface. Aimed at engineers landing in `Meshtastic/Helpers/TAK/`, `AccessoryManager+TAK.swift`, or `Views/Settings/TAKServerConfig.swift` for the first time.

For the spec / requirements: see `spec.md`. For implementation phasing and structure: see `plan.md`. For data structures: see `data-model.md`. For wire details: see `contracts/wire-protocol.md`.

---

## Prerequisites

- Xcode 16+ (Swift 5.9+, Swift Testing framework support).
- An iOS device or simulator (iOS 17.5+). Apple Silicon Mac running Mac Catalyst also works.
- Optional but recommended for end-to-end testing:
  - A Meshtastic radio with firmware ≥ 2.8.0 (for V2 path testing).
  - A second Meshtastic radio with firmware ≤ 2.7.x (for V1 ATAK_PLUGIN fallback testing).
  - iTAK installed on iPhone / iPad ([App Store](https://apps.apple.com/us/app/itak/id1561656396)) and / or ATAK Civ on Android.

## First Build

```bash
git clone https://github.com/meshtastic/Meshtastic-Apple.git
cd Meshtastic-Apple
git submodule update --init --recursive   # protobufs submodule
open Meshtastic.xcworkspace                # always the workspace, not the .xcodeproj
```

Build the `Meshtastic` scheme for an iPhone simulator. The `TAKPacket-SDK` Swift Package resolves from `Meshtastic.xcworkspace/.../Package.resolved` (pinned `0.2.3`). First-time resolution takes ~30 seconds.

## Run the TAK-Tagged Tests

The Swift Testing framework exposes test filtering by file:

```bash
xcodebuild test \
  -workspace Meshtastic.xcworkspace \
  -scheme Meshtastic \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MeshtasticTests/TAKBridgeTests \
  -only-testing:MeshtasticTests/TAKBridgeDetailedTests \
  -only-testing:MeshtasticTests/TAKCodecTests \
  -only-testing:MeshtasticTests/CoTMessageTests \
  -only-testing:MeshtasticTests/CoTMessageDetailedTests \
  -only-testing:MeshtasticTests/CoTXMLParserTests \
  -only-testing:MeshtasticTests/CoTExtensionTests \
  -only-testing:MeshtasticTests/GenericCoTHandlerTests
```

Or just run all tests:

```bash
xcodebuild test -workspace Meshtastic.xcworkspace -scheme Meshtastic \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

## Architecture at a Glance

```
                       ┌──────────────────────┐
                       │  iTAK / ATAK Civ     │
                       │  (port 8089, mTLS)   │
                       └──────────┬───────────┘
                                  │
                                  ▼
                     ┌─────────────────────────┐
                     │   TAKServerManager      │ ← NWListener, offline queue,
                     │   (Helpers/TAK)         │   per-client connections
                     └────┬────────────────┬───┘
                          │                │
              broadcast()│                │ inbound CoTMessage (from client)
                          ▼                ▼
                     ┌─────────────────────────┐
                     │  TAKMeshtasticBridge    │ ← sendToMesh: V1/V2 fork
                     │  (Helpers/TAK)          │   receivedFromMesh: dispatch
                     └────┬────────────────┬───┘
                          │                │
                          │                │ sendCoTToMeshV2 / sendTAKPacket /
            broadcast()  │                │ GenericCoTHandler.sendGenericCoT
            broadcastRawXml                ▼
                          │       ┌─────────────────────────┐
                          │       │ AccessoryManager+TAK    │ ← send / receive
                          │       │ (Accessory Manager)     │   handlers per portnum
                          │       └────┬────────────────────┘
                          │            │
                          │            │ MeshPacket on port 72 / 78 / 257
                          │            ▼
                          │       ┌─────────────────────────┐
                          │       │ AccessoryManager         │ ← BLE / TCP / Serial
                          │       │ (BLE / TCP / Serial)     │   transports
                          │       └────┬────────────────────┘
                          │            │
                          │            │ to Meshtastic firmware → LoRa
                          │            ▼
                          │       ┌─────────────────────────┐
                          │       │     LoRa Mesh            │
                          │       └─────────────────────────┘
                          │
                          └──── route CoT receive: also writes
                                Documents/TAK Routes/<uid>.zip
                                and posts "Route Received" notification
```

---

## Common Tasks

### Task 1: Trace a CoT Send (TAK Client → Mesh)

You want to follow an event from iTAK drawing a circle on the map to it appearing on a remote iTAK over the mesh.

1. **Entry**: `TAKConnection.handleReceivedData(_:)` parses framed CoT XML and emits `.message(CoTMessage, TAKClientInfo?)`.
2. **Dispatch**: `TAKServerManager` forwards the message to `TAKMeshtasticBridge.sendToMesh(_:clientInfo:)`.
3. **Enrichment**: For GeoChat without a `<contact>`, synthesize one from `clientInfo` or `<__chat senderCallsign>`.
4. **Fork on `supportsTAKv2`**:
   - **V2 branch**: `cotMessage.sourceEventXml` (preferred) or `enrichedMessage.toXML()` → `accessoryManager.sendCoTToMeshV2(_:channel:)` → SDK parse → compress → `sendTAKV2Packet` on port 78.
   - **V1 branch**: `GenericCoTHandler.classifySendMethod(for:)` → `.takPacketPLI/.takPacketChat` → `convertToTAKPacket` → `sendTAKPacket` on port 72. OR `.exiDirect/.exiFountain` → `GenericCoTHandler.sendGenericCoT` on port 257.

Set a breakpoint in `TAKMeshtasticBridge.swift:187` (the `if accessoryManager.supportsTAKv2` line) to watch the fork happen.

### Task 2: Trace a CoT Receive (Mesh → TAK Client)

1. **Entry**: `AccessoryManager.swift` dispatch loop receives a `MeshPacket`, switches on `decodedInfo.packet.decoded.portnum`.
2. **V2 branch (portnum 78)**: `handleATAKPluginV2Packet(_:)` → `Task.detached(priority: .utility)` → SDK decompress → SDK build CoT XML → strip prologue/whitespace → `TAKServerManager.shared.broadcastRawXml(_:)`. For routes: also `RouteDataPackageGenerator.generateDataPackage` → `saveToDocuments` → `LocalNotificationManager.schedule`.
3. **V1 ATAK_PLUGIN branch (portnum 72)**: `handleATAKPluginPacket(_:)` → decode `TAKPacket` proto → `CoTMessage(takPacket:)` → `TAKServerManager.shared.broadcast(_:)`.
4. **V1 ATAK_FORWARDER branch (portnum 257)**: `handleATAKForwarderPacket(_:)` → `GenericCoTHandler.handleIncomingForwarderPacket(_:)` → Fountain reassembly → EXI/zlib decode → broadcast.

### Task 3: Add a New V2 Strip Pattern

`stripNonEssentialElements(_:)` lives in `AccessoryManager+TAK.swift` around line 422. Adding a new strip:

1. Identify the bloat element in a captured iTAK / ATAK Civ CoT XML (use the in-app TAK Test screen or `Logger.tak.debug` logs).
2. Add an entry to the `patterns` array. Use `[^>]*` for attribute-tolerant matching, and add both self-closing (`<foo[^>]*/>`) and paired (`<foo[^>]*>.*?</foo>`) variants when ATAK / iTAK can emit either.
3. Make sure the regex uses `[.dotMatchesLineSeparators]` (it does — set globally in the existing factory).
4. Add a test to `MeshtasticTests/TAKBridgeDetailedTests.swift` or `CoTXMLParserTests.swift` asserting the pattern is stripped.

### Task 4: Update the TAKPacket-SDK Pin

When a new SDK release lands (and Android has bumped `core/proto/build.gradle.kts` in the corresponding PR):

1. In Xcode, open `File → Packages → Update to Latest Package Versions`.
2. Or edit `Meshtastic.xcworkspace/xcshareddata/swiftpm/Package.resolved` directly: bump `revision` and `version` for `TAKPacket-SDK`.
3. Also bump `MeshtasticProtobufs/Package.resolved` to keep the embedded package in sync.
4. Build, run the full test suite (especially `TAKBridgeTests` and `TAKCodecTests`).
5. Manually exercise the V2 send and receive paths against a V2-capable radio with iTAK connected.
6. If the SDK changed any wire-format-affecting behavior (compression dict, schema), update `contracts/wire-protocol.md` and bump the spec date.

### Task 5: Add a New TAK-Server Setting

`TAKServerManager`'s persisted state lives in `@AppStorage` properties:

```swift
@AppStorage("takServerEnabled") var enabled = false { didSet { ... } }
@AppStorage("takServerChannel") var channel: Int = 0
@AppStorage("takServerReadOnly") var userReadOnlyMode = false
@AppStorage("takServerMeshToCot") var meshToCotEnabled = false
```

To add another:

1. Add a new `@AppStorage` property to `TAKServerManager`.
2. If the setting needs to trigger server restart, mirror the `didSet` pattern from `enabled`.
3. Add a SwiftUI control to `TAKServerConfig.swift` in the appropriate section (Server Configuration, Certificates, Data Package, etc.).
4. Use `@ObservedObject var manager = TAKServerManager.shared` to bind in the view.
5. Add tests in `MeshtasticTests/` for any behavioral implications.

### Task 6: Run iTAK or ATAK Civ Against a Local Server

1. Launch Meshtastic on iPhone / Mac Catalyst.
2. Connect to a Meshtastic radio (BLE / TCP / USB).
3. Settings → TAK Server → toggle Enable on.
4. Tap "Export Data Package" → Save to Files (or AirDrop to another device).
5. In iTAK: Settings → Servers → + → Import Data Package → pick the saved zip.
6. iTAK shows the server as Connected in green.
7. Drop a marker on iTAK; verify it appears in `Logger.tak.info("TAK → mesh: ...")` and on a peer's iTAK over the mesh.

If iTAK can't connect from off-device, iOS Settings → Privacy → Local Network → enable for Meshtastic.

### Task 7: Verify a Route Receipt End-to-End

1. Have two Meshtastic / iPhone setups, both with the app running and iTAK connected.
2. On Phone A, create a route in iTAK with 3 waypoints.
3. On Phone B, observe:
   - `Logger.tak.info("Decompressed ATAK V2 packet from node ...")` log.
   - `Logger.tak.info("Forwarded ATAK V2 to TAK clients (raw XML)")` log.
   - `Logger.tak.info("Route data package saved: <path>")` log.
   - A "Route Received" notification banner.
   - The route zip in Files → On My iPhone → Meshtastic → TAK Routes.
4. In iTAK on Phone B: Files → import the route zip → verify the route renders with all 3 waypoints.

---

## File Cheatsheet

| File | Lines | Key Symbols |
|------|-------|-------------|
| `Meshtastic/Helpers/TAK/TAKMeshtasticBridge.swift` | 1462 | `sendToMesh`, `convertToTAKPacket`, `parseReceipt`, `registerContact`, `parseDeviceCallsign`, `createSmuggledDeviceCallsign` |
| `Meshtastic/Helpers/TAK/TAKServerManager.swift` | 839 | `start`, `stop`, `broadcast`, `broadcastRawXml`, `drainOfflineQueue`, `connectedClients` |
| `Meshtastic/Helpers/TAK/TAKConnection.swift` | 550 | `connect`, `disconnect`, `startKeepalive`, `handleReceivedData`, `TAKClientInfo`, `TAKConnectionEvent` |
| `Meshtastic/Helpers/TAK/TAKCertificateManager.swift` | 788 | `loadServerCertificate`, `loadCustomServerCertificate`, `persistCustomServerCertificate`, `regenerateCertificates` |
| `Meshtastic/Helpers/TAK/CoTMessage.swift` | 545 | `CoTMessage`, `CoTContact`, `CoTGroup`, `CoTStatus`, `CoTTrack`, `CoTChat`, `init(takPacket:)`, `toXML` |
| `Meshtastic/Helpers/TAK/CoTXMLParser.swift` | 333 | `CoTXMLParser`, `parse(xmlString:)` |
| `Meshtastic/Helpers/TAK/EXICodec.swift` | 148 | `encode(_:)`, `decode(_:)` (zlib) |
| `Meshtastic/Helpers/TAK/FountainCodec.swift` | 627 | `encode(_:)`, `decode(_:)` (LT erasure codes) |
| `Meshtastic/Helpers/TAK/GenericCoTHandler.swift` | 399 | `classifySendMethod(for:)`, `sendGenericCoT(_:channel:)`, `handleIncomingForwarderPacket(_:)` |
| `Meshtastic/Helpers/TAK/RouteDataPackageGenerator.swift` | 262 | `generateKml`, `generateDataPackage`, `saveToDocuments`, `sanitizeForFilename`, `escapeXml` |
| `Meshtastic/Helpers/TAK/TAKDataPackageGenerator.swift` | 290 | `generateDataPackage()` (for client config export) |
| `Meshtastic/Accessory/Accessory Manager/AccessoryManager+TAK.swift` | 492 | `handleATAKPluginPacket`, `handleATAKForwarderPacket`, `handleATAKPluginV2Packet`, `sendTAKPacket`, `sendTAKV2Packet`, `sendCoTToMeshV2`, `stripNonEssentialElements`, `ensureMinimumStaleForMesh` |
| `Meshtastic/Accessory/Accessory Manager/AccessoryManager.swift` (line 860) | — | `supportsTAKv2` |
| `Meshtastic/Views/Settings/TAKServerConfig.swift` | 800 | `TAKServerConfig`, `TAKIdentitySection`, `ZipDocument` (`FileDocument`) |
| `Meshtastic/Views/Settings/Config/Module/TAKModuleConfig.swift` | 268 | `TAKModuleConfig` (standalone firmware module config) |

---

## Debugging Tips

### Logger Channels

All TAK code uses `Logger.tak` (defined in `OSLog` extension). Filter Console.app or `xcrun simctl spawn booted log stream` by `subsystem:"com.meshtastic.app" category:"tak"`.

### Common Failures

| Symptom | Likely Cause | Where to Look |
|---------|--------------|---------------|
| "Sent TAK V2 packet" log fires but peers don't receive | `hopLimit = 0` (firmware silently drops). Should be fixed; check `takBroadcastHopLimit(forDevice:)` returned non-zero. | `AccessoryManager+TAK.swift:sendTAKV2Packet` |
| iTAK disconnects every 15 seconds | Keepalive task not running, or `keepaliveInterval` too long. | `TAKConnection.swift:startKeepalive` |
| iTAK can't import data package | Cert chain mismatch or expired `ca.pem`. Regenerate via Settings → TAK Server → Regenerate Certificates. | `TAKCertificateManager.swift` |
| "Route Received" notification missing | Receiver didn't get past `Task.detached`. Check the V2 decompress log. Could be malformed wire bytes. | `AccessoryManager+TAK.swift:handleATAKPluginV2Packet` |
| Shape arrives without geometry | Bridge sent `toXML()` instead of `sourceEventXml`. Verify the type check on the `cotXml` line. | `TAKMeshtasticBridge.swift:194` |
| V2 send fails with `AccessoryError.ioFailed` "payload exceeds wire size" | Compressed payload too large even after `<remarks>` strip. Check the CoT shape — it likely has too many waypoints / complex detail. | `AccessoryManager+TAK.swift:sendCoTToMeshV2` |
| GeoChat receipts not surfacing | `parseReceipt` regex failed. Check the inbound message body for `ACK:D:` or `ACK:R:` prefix and a valid messageId. | `TAKMeshtasticBridge.swift` |

### Useful Breakpoints

- `TAKMeshtasticBridge.swift:187` — the V1/V2 fork
- `AccessoryManager+TAK.swift:124` — V2 receive entry
- `AccessoryManager+TAK.swift:260` — V2 send entry
- `TAKServerManager.swift:start()` — listener bind
- `TAKConnection.swift:startKeepalive` — keepalive task start

### In-App Diagnostic

There's no in-app TAK test harness yet on Apple (Android has `TakMeshTestRunner`). Adding one is on the backlog — see `tasks.md`.

---

## Coding Conventions

- **`@MainActor`**: `TAKServerManager` and `TAKMeshtasticBridge` are main-actor isolated. CPU-heavy work in `handleATAKPluginV2Packet` hops to `Task.detached(priority: .utility)`.
- **Sendability**: `CoTMessage` and its sub-types are `Sendable` (value types with `Sendable`-conforming fields). New CoT-domain types should follow the same pattern.
- **No force-unwraps**: Use `guard let` / `if let`; surface errors via `Logger.tak.error` or `AccessoryError`.
- **No `print`**: Always use `Logger.tak` so output is searchable via Console.app and the in-app log viewer.
- **SDK imports**: `import MeshtasticTAK` (not `import TAKPacket_SDK` or similar — the module name is `MeshtasticTAK`).
- **AppStorage keys**: Prefix with `takServer` so they group together in user defaults browsers.
- **Tests**: Swift Testing framework (`@Suite`, `@Test`). Don't add XCTest cases; the project standardized on Swift Testing.

---

## Where Things Don't Live

To prevent the next-engineer rabbit-hole:

- **There is no `core:takserver` module on Apple** — Apple is single-target. Everything lives in `Meshtastic/Helpers/TAK/`.
- **There is no `commonMain` source set** — Apple isn't KMP. The naming convention is iOS-flat.
- **There is no PARTIAL_WAKE_LOCK equivalent** — iOS doesn't expose one. Reliability is bounded by BLE-peripheral background mode.
- **There is no `useTakV2()` per-send function** — Apple inlines the `accessoryManager.supportsTAKv2` check in `sendToMesh`.
- **There is no Foundation `JSON Schema` validation** — CoT XML is parsed by `CoTXMLParser` (streaming) and SDK builders / parsers; no schema validator.
- **There is no `MAX_DECOMPRESSED_SIZE` constant** — Apple delegates the limit to the SDK's `TakCompressor.decompress`.
- **There is no separate `iosMain` / `iosTest` source set** — all tests live in `MeshtasticTests/`.

---

## Next Reading

- `spec.md` — what / why / acceptance scenarios.
- `plan.md` — implementation phasing and structure.
- `data-model.md` — entities, state machines, wire-format summary.
- `research.md` — design decisions and alternatives considered.
- `contracts/wire-protocol.md` — full wire-format contract (Apple flavor).
- [Meshtastic-Android `specs/005-tak-v2-protocol`](https://github.com/meshtastic/Meshtastic-Android/tree/main/specs/005-tak-v2-protocol) — Android companion spec.
- [`meshtastic/TAKPacket-SDK`](https://github.com/meshtastic/TAKPacket-SDK) — wire-protocol source of truth (Swift Package source).
- In-app developer guide: Settings → About → Developer → TAK Protocol (renders `Meshtastic/Resources/docs/markdown/developer/tak-protocol.md`).
