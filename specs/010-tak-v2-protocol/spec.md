# Feature Specification: TAK v2 Protocol Integration (Apple)

**Feature Branch**: `spec-tak`
**Created**: 2026-05-14
**Status**: Retroactive — back-specifies the merged Apple TAK v2 implementation; companion to Meshtastic-Android [`specs/005-tak-v2-protocol`](https://github.com/meshtastic/Meshtastic-Android/tree/main/specs/005-tak-v2-protocol)
**Input**: User description: "Write an Apple spec for TAK v2 — Apple already ships TAK v2 (`supportsTAKv2`, firmware ≥ 2.8.0) but with no formal spec. An Apple companion spec scopes the iOS/macOS UX surface differences and ensures ongoing parity as the protocol evolves."
**Cross-Platform Spec**: iOS (iPhone, iPad) and macOS (via Mac Catalyst). Wire protocol defined by [TAKPacket-SDK](https://github.com/meshtastic/TAKPacket-SDK) (Swift Package via SPM); pinned at `0.2.3` in `Meshtastic.xcworkspace/.../Package.resolved`.

## Summary

This feature documents the Apple Meshtastic app's TAK (Team Awareness Kit) integration as it shipped. The app exposes a local TLS/mTLS server (port 8089) that ATAK Civ and iTAK clients connect to. Outbound CoT (Cursor-on-Target) events are forwarded over the LoRa mesh via one of three wire formats, picked per-send based on the connected radio's firmware version:

1. **V2** `ATAK_PLUGIN_V2` (port 78) — TAKPacketV2 protobuf with zstd dictionary compression via the [TAKPacket-SDK](https://github.com/meshtastic/TAKPacket-SDK). Used when `AccessoryManager.supportsTAKv2` returns true (firmware ≥ 2.8.0). Carries the full typed CoT vocabulary: PLI, GeoChat, shapes, markers, routes, casevac, emergency, task.

2. **V1 ATAK_PLUGIN** (port 72) — bare `TAKPacket` protobuf (PLI and GeoChat only). Used when the radio firmware is ≤ 2.7.x and the CoT message is a PLI or chat.

3. **V1 ATAK_FORWARDER** (port 257) — zlib-compressed CoT XML, optionally Fountain (LT) coded across multiple packets when payload exceeds one LoRa MTU. Used when the radio firmware is ≤ 2.7.x and the CoT message is anything other than PLI / GeoChat (markers, routes, shapes, etc.). The portnum itself was originally defined for the third-party [paulmandal/atak-forwarder Android plugin](https://github.com/paulmandal/atak-forwarder) (which encodes via `libcotshrink`); the Apple-side stack reimplements compatible zlib framing — see `EXICodec.swift`'s header for the "for Android interoperability" intent. In practice the common counterparty on this port is another Apple Meshtastic peer; the **official Meshtastic Android app does not implement a receive handler for port 257** (its mesh router just forwards the bytes), so an Android peer running only the official ATAK plugin won't see these packets surface. Whether the wire framing exactly matches paulmandal's `libcotshrink` output (and would therefore interop with that plugin) is asserted by code comments but not currently verified by an automated test.

The inbound path always listens on all three portnums regardless of local firmware, so a v2-capable phone connected to a 2.7.x radio still receives PLI and GeoChat from older mesh nodes, and a 2.7.x Apple phone still receives full V1 ATAK_FORWARDER traffic from other Apple peers (or any port-257-compatible source).

Architectural parity with Android is intentional for the V2 path (same wire bytes, same SDK, same prune-list and detail-stripper philosophy). Divergence is concentrated in the V1 fallback (Apple's EXI + Fountain path has no Android equivalent), the TLS stack (Network.framework vs. JSSE), the UI toolkit (SwiftUI vs. Compose Multiplatform), background-execution model (iOS background-mode entitlements vs. Android PARTIAL_WAKE_LOCK), filesystem surface (Files app + UTType vs. SAF), and permission model (Local Network entitlement vs. ACCESS_LOCAL_NETWORK).

## Goals

1. **Full CoT type coverage on V2**: Match Android's V2 type coverage byte-for-byte over the air — PLI, GeoChat, Marker, Route, DrawnShape (circle, ellipse, freeform, polygon, rectangle, telestration), Aircraft, Casevac, Emergency, Task, Ranging, Alert, Delete, Chat Receipts, Waypoints. CoT-typed payloads round-trip Apple ↔ Android via the SDK without bridging loss.
2. **Efficient wire encoding**: Same 225-byte usable LoRa wire-payload budget as Android (`maxWirePayloadBytes = 225`). Use the SDK's `compressWithRemarksFallback` to attempt full-detail compression, then re-attempt with `<remarks>` stripped if the first pass overflows. Apple additionally strips a 24-pattern element/attribute list before compression (Android strips 16) to claw back bytes on ATAK CIV's verbose detail blocks.
3. **Backward compatibility with two paths**: Auto-detect firmware version and gracefully fall back. PLI / GeoChat on legacy go via V1 ATAK_PLUGIN (port 72 — the **official Meshtastic ATAK plugin's** portnum; fully interoperable with the Meshtastic-Android app). All other CoT types on legacy fall through to V1 ATAK_FORWARDER (port 257 — originally the **paulmandal atak-forwarder Android plugin's** portnum, repurposed Apple-side for arbitrary chunked CoT XML; the Meshtastic-Android *app* does not implement a receive handler for this portnum). The threshold (firmware ≥ 2.8.0) is gated by `AccessoryManager.supportsTAKv2`.
4. **Reliable local TAK server**: Always-on TLS listener on `127.0.0.1:8089` via `Network.framework`'s `NWListener` with `NWProtocolTLS`. Survives backgrounding for as long as iOS keeps the BLE / TCP / USB transport alive (no foreground service equivalent; relies on BLE-peripheral and the AccessoryManager's background mode handoff).
5. **Route interoperability for iTAK**: iTAK silently ignores route CoT (`b-m-r`) received over its TCP streaming connection. Generate a KML-inside-zip data package and save to `Documents/TAK Routes/` so the user can sideload via the iOS Files app, plus surface a local notification ("Route Received — Saved to Files → Meshtastic → TAK Routes. Open in iTAK to import.") so the receipt is visible.
6. **Identity admin from inside TAK Server config**: Embed the firmware `ModuleConfig.TAKConfig` editor (team color + member role) inside the same screen as the in-app TAK server controls so users configure the full identity surface in one place. Use SwiftUI directly with admin-message round-trips via `AccessoryManager.requestTAKModuleConfig` / `saveTAKModuleConfig`.

## Non-Goals

- Implementing a full TAK Server with mission sync, federation, or enterprise features (same as Android).
- Supporting TAK protocols over non-mesh transports (WiFi-direct, Bluetooth peer-to-peer).
- Modifying the Meshtastic firmware or protobuf schema (consumed read-only from upstream).
- Providing a standalone TAK client UI within the Meshtastic app (ATAK and iTAK remain the clients).
- Supporting CoT streaming to remote TAK servers over the internet.
- macOS-native (AppKit) TAK Server UI — runs via Mac Catalyst with the iOS SwiftUI surface.
- Watch / TV / visionOS surface — out of scope; AccessoryManager limits TAK to iOS / iPadOS / macCatalyst.
- Pure macOS (non-Catalyst) builds — `targetEnvironment(macCatalyst)` adds a `SerialTransport` for the lab; standalone macOS isn't a supported deployment target.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Send Rich Tactical Data Over Mesh (Priority: P1)

A TAK operator using iTAK on iPhone connects to the Meshtastic app's built-in TAK server (data package import) and drops a marker, draws a shape, or creates a route on the iTAK map. The Meshtastic app converts the CoT event into a compressed TAKPacketV2 and transmits it over the mesh. All other mesh nodes with TAK-connected clients see the marker / shape / route appear on their maps. For routes specifically, the receiving Apple node also writes a KML data package to `Documents/TAK Routes/` and posts a "Route Received" notification so the user can sideload it into iTAK.

**Why this priority**: This is the core value proposition — extending TAK's situational awareness beyond PLI to include all tactical overlays over LoRa mesh, with the iTAK route-import affordance closing the one workflow gap iTAK has.

**Independent Test**: Connect two Meshtastic radios (firmware ≥ 2.8.0) each with iTAK or ATAK Civ connected. Drop a hostile marker on one client and verify it appears on the other with correct type, icon, and position. For routes, verify the "Route Received" local notification fires and that `Documents/Meshtastic/TAK Routes/<sanitized-uid>.zip` exists and opens cleanly in iTAK's "Import" sheet.

**Acceptance Scenarios**:

1. **Given** two mesh nodes running firmware ≥ 2.8.0 with TAK clients (iTAK and / or ATAK Civ) connected, **When** a user places a marker (type `a-h-G`) on one TAK client, **Then** the marker appears on the remote TAK client with correct hostile type, position, and callsign within one mesh transmission cycle.
2. **Given** a mesh node with firmware ≥ 2.8.0, **When** a TAK user creates a route with 3 waypoints, **Then** the route is transmitted over port 78 AND on the receiving node `Documents/TAK Routes/<sanitized-uid>.zip` is created and a `Notification` with title "Route Received" is posted via `LocalNotificationManager`.
3. **Given** a TAKPacketV2 payload exceeding 225 bytes after compression and remarks stripping, **When** the system attempts transmission, **Then** it throws `AccessoryError.ioFailed("TAK V2 payload exceeds LoRa wire size limit ...")` from `sendCoTToMeshV2(_:channel:)` so `TAKMeshtasticBridge.sendToMesh` logs the failure rather than treating the drop as a successful send.

---

### User Story 2 — Legacy Fallback for Mixed Firmware (Priority: P1)

A team has a mix of older radios (firmware 2.7.x) and newer radios (firmware 2.8.0+). The app detects each radio's capability and uses the appropriate protocol version. PLI and GeoChat round-trip Apple ↔ Android on V1 (port 72). For non-PLI / non-GeoChat CoT types on legacy radios, Apple peers exchange full CoT over V1 ATAK_FORWARDER (port 257) via Apple's EXI + Fountain stack; Android-to-Apple traffic for these types is dropped at the Android sender (Android logs a warning rather than attempt the Apple-only fallback).

**Why this priority**: Mixed-firmware deployments are the reality during any firmware upgrade cycle; breaking backward compatibility would render the feature unusable for most teams. Apple's V1 ATAK_FORWARDER path is the only way to ship shapes / markers / routes between two Apple peers when neither radio supports V2.

**Independent Test**: Connect two iPhones each paired with firmware-2.7.x radios. Drop a marker on iTAK A; confirm it appears on iTAK B via the ATAK_FORWARDER path. Reconnect iPhone A to a firmware-2.8.0+ radio mid-session; confirm the next marker drop goes out on port 78 (V2) without restarting the app.

**Acceptance Scenarios**:

1. **Given** a radio running firmware < 2.8.0, **When** a TAK user sends a PLI update, **Then** the app encodes it as a legacy `TAKPacket` on port 72 (`ATAK_PLUGIN`) via `sendTAKPacket(_:channel:)`.
2. **Given** a radio running firmware < 2.8.0, **When** a TAK user drops a marker, **Then** `GenericCoTHandler.classifySendMethod` returns `.exiDirect` or `.exiFountain` and the app encodes the CoT XML via the EXI + Fountain pipeline and sends it on port 257 (`ATAK_FORWARDER`). Receiving Apple peers reassemble and decode; receiving Android peers see only opaque bytes.
3. **Given** a radio running firmware ≥ 2.8.0, **When** a legacy `TAKPacket` arrives on port 72 from an older mesh node, **Then** `handleATAKPluginPacket(_:)` decodes it, converts to `CoTMessage`, and `TAKServerManager.shared.broadcast(_:)` forwards it to connected TAK clients.
4. **Given** a radio that upgrades firmware OTA mid-session, **When** the next CoT send happens, **Then** the per-send `accessoryManager.supportsTAKv2` check picks up the new firmware version and switches to V2 immediately (no app restart required — the fork is per-send, not per-session).

---

### User Story 3 — TAK Server Lifecycle and Reliability (Priority: P2)

A user enables the TAK server from the Meshtastic app's Settings → TAK Server screen. The server starts an `NWListener` with mTLS on `127.0.0.1:8089`, accepts ATAK Civ / iTAK connections, and remains operational across screen-off and background transitions for as long as iOS keeps the BLE / TCP transport alive via the app's BLE-peripheral background mode. Users can export a connection data package (`.zip` with `.p12` certs + ATAK `.pref` file) via the SwiftUI `fileExporter` modifier, opening the system share sheet so the file can be AirDropped, saved to Files, or attached to a message.

**Why this priority**: Without a reliable local server, TAK clients cannot maintain connectivity, making all other features unreliable.

**Independent Test**: Enable TAK server from Settings → TAK Server. Tap "Export Data Package" → save to Files. Open iTAK, import the data package, verify TLS connection to `127.0.0.1:8089` succeeds. Background the Meshtastic app for 10 minutes (screen off), bring it back, confirm iTAK still shows connected.

**Acceptance Scenarios**:

1. **Given** the TAK server is disabled, **When** the user toggles `takServerEnabled` to `true` in Settings, **Then** `TAKServerManager.shared.start()` runs (via the `didSet` observer on `enabled`), an `NWListener` binds 8089 / TLS, and the UI shows `isRunning = true` with `connectedClients.count = 0`.
2. **Given** the TAK server is running with iTAK connected, **When** the device screen turns off, **Then** the TLS connection is held by `NWConnection` and the per-client keepalive task (10-second interval, well under ATAK's 15-second `RX_STALE_SECONDS`) continues running for the duration of the BLE / TCP transport's background allowance. (No PARTIAL_WAKE_LOCK equivalent on iOS; reliability is bounded by iOS background-mode policy.)
3. **Given** the TAK server is running, **When** the user taps "Export Data Package," **Then** `TAKDataPackageGenerator.generateDataPackage()` produces a `.zip` containing `truststore.p12`, `client.p12`, `meshtastic-server.pref`, and `manifest.xml`. The SwiftUI `fileExporter` modifier opens the share sheet so the file can be saved to Files, AirDropped, or imported directly by ATAK / iTAK.

---

### User Story 4 — TAK Identity + Server Configuration (Priority: P2)

A user navigates to Settings → TAK Server. The screen renders, top to bottom: the firmware `ModuleConfig.TAKConfig` editor (team color + member role) as `TAKIdentitySection`, the in-app TAK server controls (Enable, channel, read-only mode), certificate management (import / regenerate `.p12`), and data package export. Toggling Enable starts / stops the server. Saving identity sends an admin message via `AccessoryManager.saveTAKModuleConfig` to update the connected radio's firmware module config.

**Why this priority**: Users need a single screen to configure their tactical identity (team / role) AND the local server. Splitting these across two screens (as Android does separately in Module Config → TAK and Settings → TAK Server) creates discoverability friction; combining them was a deliberate Apple-side choice.

**Independent Test**: Navigate to Settings → TAK Server. Change team color to "Cyan" and role to "Team Member". Verify outgoing PLI packets carry the selected team and role. Toggle Enable off and on; verify server restart. Tap "Regenerate Certificates"; verify new `.p12` files are persisted and previously-connected clients are disconnected (must re-import the data package).

**Acceptance Scenarios**:

1. **Given** the user is on Settings → TAK Server, **When** they select a team color and role and tap "Save Identity," **Then** `AccessoryManager.saveTAKModuleConfig(config:fromUser:toUser:)` packages a `ModuleConfig.TAKConfig` in an `AdminMessage` and ships it on the admin port. Subsequent V2 outbound PLIs carry the new team / role values.
2. **Given** the user is on Settings → TAK Server and the connected node has no cached TAK config, **When** the screen appears, **Then** `requestTakConfigIfNeeded()` fires an admin request via `AccessoryManager.requestTAKModuleConfig(fromUser:toUser:)` so first-time users don't see a perma-spinner.

---

### User Story 5 — Inbound Dual-Path Tolerance (Priority: P3)

A v2-capable node receives packets from V1 (port 72), V1 ATAK_FORWARDER (port 257), and V2 (port 78). All three are decoded and forwarded to connected TAK clients regardless of the local radio's firmware version. V2 raw XML is forwarded via `broadcastRawXml` to preserve shape geometry (link-point vertices, colors); V1 paths convert to `CoTMessage` and forward via `broadcast`.

**Why this priority**: Ensures no tactical data is lost in mixed deployments where some nodes only send V1 (Android or Apple) and some send V1 ATAK_FORWARDER (Apple-to-Apple shapes).

**Independent Test**: Send a legacy `TAKPacket` (port 72) PLI from an Android peer to an Apple node on firmware ≥ 2.8.0; verify the iTAK client receives the PLI. Send a Fountain-coded shape from another Apple peer on firmware ≤ 2.7.x; verify the iTAK client receives the shape after reassembly.

**Acceptance Scenarios**:

1. **Given** a node with firmware ≥ 2.8.0, **When** it receives a `TAKPacket` on port 72, **Then** `handleATAKPluginPacket(_:)` decodes the packet and broadcasts it to connected TAK clients.
2. **Given** a node with firmware ≥ 2.8.0, **When** it receives a `TAKPacketV2` on port 78, **Then** `handleATAKPluginV2Packet(_:)` decompresses on a detached utility-priority `Task` (so the main actor doesn't stall on large routes), rebuilds the CoT XML via `MeshtasticTAK.CotXmlBuilder`, strips the XML prologue and inter-tag whitespace, and forwards the raw XML via `TAKServerManager.shared.broadcastRawXml(_:)`.
3. **Given** an Apple node on any firmware, **When** it receives an `ATAK_FORWARDER` (port 257) packet, **Then** `handleATAKForwarderPacket(_:)` hands off to `GenericCoTHandler.handleIncomingForwarderPacket(_:)`, which reassembles Fountain fragments and zlib-decompresses the resulting CoT XML before forwarding to TAK clients.

---

### Edge Cases

- What happens when V2 zstd decompression produces malformed protobuf? → `try compressor.decompress(wirePayload)` throws; the detached `Task` catches and logs `Failed to decompress ATAK V2 packet:` without dropping any other in-flight traffic.
- What happens when the TAK server port 8089 is already in use? → `NWListener` start fails and `TAKServerManager.lastError` is populated with a user-visible string; the toggle in Settings returns to off.
- What happens when a CoT XML contains malformed or hostile content? → `stripNonEssentialElements` regex-strips 24 patterns including unknown-value attributes (`xxx="???"`) before compression; the receiver's `CoTXmlBuilder` rebuilds well-formed XML; the prologue-regex defends against `<?xml ...?>` mid-stream which would tear down the TCP connection.
- What happens when iTAK sends a CoT type the SDK parser doesn't recognize? → `MeshtasticTAK.CotXmlParser.parse(_:)` throws; `sendCoTToMeshV2` catches it and the bridge logs `Failed to send V2 to mesh:` — the bridge does NOT fall back to V1 ATAK_FORWARDER from a V2-capable radio (no V2 receiver path for partial conversions).
- What happens when a connected TAK client disconnects and reconnects within 5 minutes? → `TAKServerManager`'s `offlineQueue` (50-message cap, 5-minute TTL) holds both `.message` (parsed CoT) and `.rawXml` (V2 shape/route detail) entries; `drainOfflineQueue()` dispatches the right path per payload variant on the next `onClientConnected` callback.
- What happens when the user denies the Local Network permission prompt on iOS 14+? → The `NWListener` binds successfully to `127.0.0.1` but is unreachable from off-device clients (still works for iTAK / ATAK running on the same iPhone or via Hotspot when the user grants Local Network later). iOS auto-prompts on first inbound connection attempt; the app does not pre-request.
- What happens when the user runs the app via Mac Catalyst? → `TAKServerManager` runs the same NWListener path. `TAKServerConfig` renders via the Catalyst SwiftUI bridge. There is no `Documents/TAK Routes/` notification on macOS (still saved; user opens via Finder).
- What happens when the radio's firmware version is unknown (handshake not yet complete)? → `checkIsVersionSupported(forVersion: "2.8.0")` returns false on missing metadata, so the bridge defaults to V1. After the first myNodeInfo, subsequent sends pick the right path automatically.
- What happens when `GenericCoTHandler` classifies a CoT as `.exiFountain` but only one fragment is sent before the app backgrounds? → Fountain (LT) codes are erasure-tolerant; the receiving Apple peer waits for enough fragments to decode. If too few arrive before the per-message timeout, the receiver drops silently.
- What happens when iTAK receives a `b-m-r` route over its TCP streaming connection? → iTAK silently ignores the event (this is a known iTAK limitation). The receiving Apple node always also writes the KML data package and posts the "Route Received" notification so the user has a recovery path.

## Architecture

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| `TAKMeshtasticBridge` | `Meshtastic/Helpers/TAK/TAKMeshtasticBridge.swift` | Bidirectional bridge; per-send V1 / V2 fork in `sendToMesh(_:clientInfo:)`. |
| `TAKServerManager` | `Meshtastic/Helpers/TAK/TAKServerManager.swift` | `NWListener` lifecycle, mTLS setup via `NWProtocolTLS`, per-client connection management, offline queue (50 / 5 min). |
| `TAKConnection` | `Meshtastic/Helpers/TAK/TAKConnection.swift` | Per-client `NWConnection` state machine, framing buffer, 10-second keepalive task. |
| `TAKCertificateManager` | `Meshtastic/Helpers/TAK/TAKCertificateManager.swift` | `.p12` loading (bundled + Keychain-stored custom), regenerate, mTLS trust evaluation. |
| `AccessoryManager+TAK` | `Meshtastic/Accessory/Accessory Manager/AccessoryManager+TAK.swift` | Send / receive handlers for all three portnums (`atakPlugin`, `atakPluginV2`, `atakForwarder`). |
| `CoTMessage` / `CoTXMLParser` | `Meshtastic/Helpers/TAK/CoTMessage.swift`, `CoTXMLParser.swift` | Domain model + streaming parser for inbound CoT from TAK clients. |
| `GenericCoTHandler` | `Meshtastic/Helpers/TAK/GenericCoTHandler.swift` | V1-only: classifies non-PLI / non-GeoChat CoT into `.exiDirect` / `.exiFountain`, dispatches over `ATAK_FORWARDER`. |
| `EXICodec` | `Meshtastic/Helpers/TAK/EXICodec.swift` | zlib compression for the V1 ATAK_FORWARDER path. |
| `FountainCodec` | `Meshtastic/Helpers/TAK/FountainCodec.swift` | Luby-Transform fountain codes for multi-fragment V1 ATAK_FORWARDER payloads. |
| `RouteDataPackageGenerator` | `Meshtastic/Helpers/TAK/RouteDataPackageGenerator.swift` | Converts route CoT (`b-m-r`) to KML-inside-zip. Writes to `Documents/TAK Routes/<sanitizedUid>.zip`. |
| `TAKDataPackageGenerator` | `Meshtastic/Helpers/TAK/TAKDataPackageGenerator.swift` | Generates the connection `.zip` for ATAK / iTAK import (`.p12` + `.pref` + manifest). |
| `TAKServerConfig` | `Meshtastic/Views/Settings/TAKServerConfig.swift` | Combined SwiftUI screen: identity (`TAKIdentitySection`) + server toggle + cert mgmt + data package export. |
| `TAKModuleConfig` | `Meshtastic/Views/Settings/Config/Module/TAKModuleConfig.swift` | Standalone firmware module config screen (also accessible from Module Config nav; same backing admin-message round-trips as `TAKIdentitySection`). |
| `ZipDocument` | `Meshtastic/Views/Settings/TAKServerConfig.swift` (`struct ZipDocument: FileDocument`) | UTType-typed `FileDocument` for SwiftUI `fileExporter`. |
| `AccessoryManager.supportsTAKv2` | `Meshtastic/Accessory/Accessory Manager/AccessoryManager.swift:860` | `checkIsVersionSupported(forVersion: "2.8.0")` — single gate property used by the bridge. |

### Comparison with Android Architecture

| Concern | Android (Kotlin / KMP) | Apple (Swift / SwiftUI) |
|---------|------------------------|-------------------------|
| TLS server stack | `javax.net.ssl.SSLServerSocket` (JSSE), `BufferedOutputStream` + `writeMutex` for stream framing | `Network.framework` (`NWListener`, `NWConnection`, `NWProtocolTLS`), per-connection serial queue |
| Background execution | `PARTIAL_WAKE_LOCK` held by `MeshService` foreground service | No equivalent; relies on BLE-peripheral background mode of the AccessoryManager transport |
| Permission model | `ACCESS_LOCAL_NETWORK` runtime permission (Android 17+, API 37) | Local Network entitlement, auto-prompted by iOS on first inbound LAN connection attempt |
| UI toolkit | Compose Multiplatform (KMP, shared with iOS stubs) | SwiftUI (iOS / iPadOS / macCatalyst); no shared KMP UI on Apple |
| File export | Storage Access Framework (SAF) document picker, written to `Documents` provider | SwiftUI `fileExporter` modifier with `UTType` typing; `Documents/TAK Routes/` integrated with Files app |
| Route receipt UX | KML written to app-private dir; no notification in current Android impl | KML written to `Documents/TAK Routes/`; local notification ("Route Received") posted via `LocalNotificationManager` |
| V1 fallback for non-PLI/Chat | **Dropped** with warning log | **ATAK_FORWARDER (port 257)**: zlib + Fountain codes — Apple-to-Apple only |
| Test surface | Multiplatform tests in `commonTest` with shared fixtures | Swift Testing framework (`@Suite`, `@Test`) in `MeshtasticTests/`; ~172 TAK-tagged tests across 8 files |
| SDK consumption | Gradle / JitPack: `com.github.meshtastic.TAKPacket-SDK:takpacket-sdk:v0.2.3` | SPM: `https://github.com/meshtastic/TAKPacket-SDK.git` pinned at `0.2.3` |
| Detail strip count | 16 element patterns | 24 patterns (24 elements + 6 attributes + UID-stripping on route waypoint `<link>` elements) |

The wire formats and CoT type mappings are identical (defined by the SDK). All divergence is at the platform-integration layer.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect firmware version via `AccessoryManager.supportsTAKv2` (`checkIsVersionSupported(forVersion: "2.8.0")`) and use TAKPacketV2 (port 78) for radios ≥ 2.8.0, falling back to the V1 dispatch table for older firmware.
- **FR-002**: System MUST support encoding and decoding of all CoT types covered by `TAKPacket-SDK` 0.2.3 on the V2 path: PLI, GeoChat, Marker, Route, DrawnShape (circle, ellipse, freeform, polygon, rectangle, telestration), Aircraft, Casevac, Emergency, Task, Ranging, Alert, Delete, Chat Receipts, Waypoints.
- **FR-003**: System MUST compress V2 outbound payloads via `MeshtasticTAK.TakCompressor().compressWithRemarksFallback(_:maxWireBytes:)`, which selects the right zstd dictionary (aircraft vs non-aircraft) and attempts a remarks-stripped retry on overflow.
- **FR-004**: System MUST throw `AccessoryError.ioFailed` from `sendCoTToMeshV2` when `compressWithRemarksFallback` returns `nil` (payload exceeds 225 bytes even without `<remarks>`), so the caller's `do/catch` doesn't treat the drop as a successful send.
- **FR-005**: System MUST accept inbound packets on all three portnums (`atakPlugin` 72, `atakForwarder` 257, `atakPluginV2` 78) regardless of local firmware version.
- **FR-006**: System MUST run a local mTLS server on port 8089 (`TAKServerManager.defaultTLSPort`) via `Network.framework`'s `NWListener` with `NWProtocolTLS` and `tcp.enableKeepalive = true`, `keepaliveIdle = 60`.
- **FR-007**: System MUST send TAK-protocol keepalive ping events at 10-second intervals from `TAKConnection.startKeepalive()` to remain below ATAK's 15-second `RX_STALE_SECONDS` threshold.
- **FR-008**: System MUST generate KML data packages for route CoT (`b-m-r`) events via `RouteDataPackageGenerator.generateDataPackage(routeXml:)` and write them to `Documents/TAK Routes/<sanitizedUid>.zip` on receive. iOS surface MUST post a `LocalNotificationManager` notification titled "Route Received" with subtitle = route callsign and body = "Saved to Files → Meshtastic → TAK Routes. Open in iTAK to import."
- **FR-009**: System MUST export connection data packages via `TAKDataPackageGenerator.generateDataPackage()` containing `truststore.p12`, `client.p12`, `meshtastic-server.pref`, and `manifest.xml`, surfaced through the SwiftUI `fileExporter` modifier with `UTType.zip`.
- **FR-010**: System MUST sanitize route UIDs via `RouteDataPackageGenerator.sanitizeForFilename(_:)` (strips path separators, control characters, and `..` sequences) before constructing file paths, and MUST escape values via `escapeXml(_:)` before interpolation into the manifest's `value="..."` attribute.
- **FR-011**: System MUST preserve the source event XML for V2 outbound when the CoT type is not `b-t-f` (GeoChat) so the SDK parser receives the original element shape (vertices, colors) — `cotMessage.sourceEventXml` is preferred over `enrichedMessage.toXML()` for non-chat events.
- **FR-012**: System MUST drop V2-only CoT types when the radio is on legacy firmware AND the type is not classifiable as `.takPacketPLI` / `.takPacketChat` / `.exiDirect` / `.exiFountain` (no V1 representation). The drop MUST be logged but not bubbled up to the user — the V1 ATAK_FORWARDER fallback covers all reachable cases between Apple peers.
- **FR-013**: System MUST strip 24 element / attribute patterns from outbound V2 CoT via `stripNonEssentialElements(_:)` before compression — including `<takv>`, `<voice>`, `<marti>`, `<__geofence>`, `<__shapeExtras>`, `<creator>`, empty `<remarks>`, `<strokeStyle>`, `<precisionlocation>` / `<precisionLocation>` (both casings), empty / placeholder attributes, and `uid="..."` on route waypoint `<link>` elements (~40 bytes saved per waypoint).
- **FR-014**: System MUST maintain an offline message queue with both `.message(CoTMessage)` and `.rawXml(String)` variants (50-entry cap, 5-minute TTL) in `TAKServerManager` and drain on `onClientConnected`. The `.rawXml` variant preserves V2 shape/route detail elements that `CoTMessage` strips.
- **FR-015**: System MUST extend `stale` timestamps of static-object CoT (routes, shapes, markers) up to `minimumMeshStaleTTL = 15 minutes` from now in `ensureMinimumStaleForMesh(_:)` so multi-hop mesh delivery doesn't deliver objects that immediately appear stale. The extension preserves the original stale only when it's already ≥ now + 15 min.
- **FR-016**: System MUST enrich GeoChat (`b-t-f`) CoT with a synthesized `<contact callsign="...">` element when the source XML lacks one (iTAK / ATAK put sender identity in `<__chat senderCallsign>` instead). The fallback chain is `cotMessage.chat?.senderCallsign` → `clientInfo?.callsign` → literal `"UNKNOWN"`. Applies only on the outbound (TAK client → mesh) path.
- **FR-017**: System MUST set `meshPacket.hopLimit` on V2 sends from `takBroadcastHopLimit(forDevice:)` (LoRa-config value with 3-hop fallback) — the protobuf default of 0 makes firmware treat the packet as already-exhausted and silently drop before TX.
- **FR-018**: System MUST process incoming V2 packets on a detached `Task.detached(priority: .utility)` so zstd decompression, KML / zip generation, and `Data.write(to:)` into `Documents/TAK Routes/` don't stall the `@MainActor` `AccessoryManager` dispatch loop. Notifications are dispatched back to `MainActor` for `LocalNotificationManager`.
- **FR-019**: System MUST strip the `<?xml ...?>` prologue and inter-tag whitespace from rebuilt V2 CoT XML before forwarding to TAK clients — leaking a mid-stream prologue tears down the iTAK / ATAK TCP streaming parser. Regex-based strip (`^\s*<\?xml[^>]*\?>`) so it works even if the SDK ever emits single quotes / different attribute order.
- **FR-020**: System MUST embed the firmware `ModuleConfig.TAKConfig` editor (`TAKIdentitySection`) inside `TAKServerConfig` and trigger `requestTakConfigIfNeeded()` on appear so first-time users see populated team / role values rather than a perma-spinner.

### Non-Functional Requirements

- **NFR-001**: Compressed V2 wire payloads MUST fit within `maxWirePayloadBytes = 225` bytes for single-packet LoRa transmission.
- **NFR-002**: TAK client connection SHOULD survive screen-off for the duration of the BLE / TCP / USB transport's background allowance — no PARTIAL_WAKE_LOCK equivalent on iOS, but `NWConnection` keepalive (`keepaliveIdle = 60` at the TCP layer, plus 10s app-layer pings) keeps NAT mappings and idle-timeouts at bay.
- **NFR-003**: V2 receive processing (zstd decompress + XML rebuild + optional KML/zip write) MUST NOT block the `@MainActor` `AccessoryManager` dispatch loop — `handleATAKPluginV2Packet` MUST hop to `Task.detached(priority: .utility)`.
- **NFR-004**: Route KML data packages MUST be written to `Documents/TAK Routes/`, accessible to the user via the Files app without any additional permission grant. App-private container is sufficient; no `MANAGE_EXTERNAL_STORAGE`-equivalent is required (iOS Files just shows `Documents`).
- **NFR-005**: Apple SDK pin MUST track Android's released version. When Android bumps `takpacket-sdk` in `core/proto/build.gradle.kts`, Apple's `Package.resolved` SHOULD be updated to the same release tag in the same PR cycle to avoid wire-format drift.

## Apple-Specific UX Surface

This section is the part Android's spec doesn't have: the iOS / macOS app surface elements that exist purely because Apple's platform model differs.

### Settings Navigation

```
Settings (root)
└── Modules
    └── TAK Server  ← single nav entry to the combined screen (target.icon)
        ├── TAKIdentitySection (firmware ModuleConfig.TAKConfig)
        │   ├── Team color picker (Cyan / Red / Blue / Green / ... )
        │   └── Member role picker (Team Member / TeamLead / HQ / ... )
        ├── Primary Channel Warning (if channel name conflicts)
        ├── Server Status section
        │   ├── isRunning indicator
        │   ├── Connected clients list
        │   └── lastError display
        ├── Server Configuration section
        │   ├── Enable toggle (@AppStorage takServerEnabled)
        │   ├── Channel picker (@AppStorage takServerChannel)
        │   └── Read-only mode toggle
        ├── Certificates section
        │   ├── Import custom .p12 (fileImporter)
        │   ├── Regenerate certificates
        │   └── Reset to bundled defaults
        └── Data Package section
            └── Export connection .zip (fileExporter → share sheet)
```

Also accessible from **Module Configuration → TAK** (same `SettingsNavigationState.tak` destination → same `TAKServerConfig`). Both nav entry points were intentionally pointed at the combined screen rather than the standalone `TAKModuleConfig` so users see the full identity + server surface in one place.

### Files App Integration

- **Export path**: SwiftUI `fileExporter` on the "Export Data Package" button opens the share sheet. The user picks Save to Files, AirDrop, or any registered share target (iTAK and ATAK both register data-package handlers).
- **Route receipt path**: KML data packages are written to `Documents/TAK Routes/<sanitizedUid>.zip` and become visible in the Files app under "On My iPhone → Meshtastic → TAK Routes". The "Route Received" local notification's body text tells the user the exact path.
- **Import path**: Custom `.p12` certificates use `fileImporter` (also SwiftUI) to pick from Files / iCloud Drive / third-party providers. The picked file is read into memory and persisted via `TAKCertificateManager` to Keychain-protected storage (key `tak.custom.server.p12.data`).

### Notifications

- **Notification scope**: iOS only — `LocalNotificationManager` schedules `UNUserNotification` requests with `MainActor` dispatch.
- **Trigger**: First receive of a route CoT (`b-m-r`) that successfully generates a KML data package.
- **Suppression**: None currently. Each route notification is a separate notification — multiple route receipts in quick succession produce multiple banners.

### Background Execution

iOS does not have a wake-lock primitive. Reliability is bounded by:

1. **BLE Peripheral background mode** (`UIBackgroundModes` → `bluetooth-peripheral`): keeps the AccessoryManager BLE transport alive while suspended. This is the dominant lever for TAK server uptime when the device is on battery.
2. **NWConnection keepalive**: TCP-layer `tcp.enableKeepalive = true` with `keepaliveIdle = 60` keeps the iTAK / ATAK TCP socket alive across NAT timeouts.
3. **Per-connection 10-second pings**: app-layer ping CoT events keep the TAK protocol's `RX_STALE_SECONDS` counter under 15 seconds.

The trade-off: no equivalent of Android's PARTIAL_WAKE_LOCK + foreground-service guarantee. When iOS aggressively suspends the app (e.g., long battery-saver, low-memory eviction), TAK clients will see disconnections. The offline queue (FR-014) catches up on reconnect.

### macOS (Mac Catalyst)

Mac Catalyst runs the same SwiftUI views via the iOS framework adapter. Behavioral notes:

- TAK server runs the same `NWListener` path; binds 8089 on the Mac's loopback.
- `targetEnvironment(macCatalyst)` enables `SerialTransport` in `AccessoryManager.shared.transports` for USB-attached radios.
- File save / export uses the macOS Save Panel via Catalyst's `fileExporter` bridge.
- Local notifications are delivered via macOS Notification Center, but the body text still references "Files → Meshtastic" — the user opens the saved zip via Finder.

## Source-Set / Module Impact

Apple does NOT use KMP source sets. The closest analogs are:

| Layer | Files | Justification |
|-------|-------|---------------|
| Domain model + parser | `Meshtastic/Helpers/TAK/CoTMessage.swift`, `CoTXMLParser.swift` | Used by both V1 and V2 paths; pure Swift, no platform imports beyond `Foundation`. |
| V2 send + receive | `Meshtastic/Accessory/Accessory Manager/AccessoryManager+TAK.swift`, `Meshtastic/Helpers/TAK/TAKMeshtasticBridge.swift` (`sendToMesh` V2 branch) | Touches `MeshtasticTAK` (SDK) and `MeshtasticProtobufs`. |
| V1 ATAK_PLUGIN | `AccessoryManager+TAK.swift` (`sendTAKPacket`, `handleATAKPluginPacket`), `TAKMeshtasticBridge.convertToTAKPacket` | Used for legacy interop with Android peers. |
| V1 ATAK_FORWARDER (Apple-only) | `EXICodec.swift`, `FountainCodec.swift`, `GenericCoTHandler.swift` | Has no Android equivalent; preserved indefinitely for Apple-to-Apple legacy paths. |
| TLS server | `TAKServerManager.swift`, `TAKConnection.swift`, `TAKCertificateManager.swift` | `Network.framework` only; would not port to Android. |
| UX | `Meshtastic/Views/Settings/TAKServerConfig.swift`, `TAKModuleConfig.swift` | SwiftUI; iOS / iPadOS / macCatalyst. |
| Tests | `MeshtasticTests/{TAKBridgeTests,TAKBridgeDetailedTests,TAKCodecTests,CoTMessageTests,CoTMessageDetailedTests,CoTXMLParserTests,CoTExtensionTests,GenericCoTHandlerTests}.swift` | Swift Testing framework; ~172 `@Test` methods. |

## Design Standards Compliance

- [x] `TAKServerConfig` and `TAKIdentitySection` use standard SwiftUI `Form` / `Section` / `Label` patterns
- [x] System SF Symbols only (`target`, `network`, `lock.shield`, etc.)
- [x] VoiceOver / Accessibility: standard SwiftUI labeling on toggles, pickers, buttons
- [x] Typography: system text styles (`.title`, `.body`, `.caption`); no hand-rolled font sizes
- [x] Dynamic Type: respected (no fixed-width `Text` containers in the TAK surface)

## Privacy Assessment

- [x] No PII, location data, or cryptographic keys logged. CoT data stays local to device / mesh.
- [x] No new network calls that transmit user data (the TAK server is loopback / LAN only — does not initiate outbound connections).
- [x] Custom `.p12` certificates persisted in Keychain (`TAKCertificateManager`), not in `UserDefaults`.
- [x] `MeshtasticProtobufs` Swift Package not modified (read-only upstream).
- [x] Routes / KML packages written to app-private `Documents/`; user has full access to delete via Files app.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All SDK-defined CoT types round-trip Apple → mesh → Android (and vice versa) without bridging loss on the V2 path — verified by cross-platform fixture tests using shared fixtures from the SDK repo.
- **SC-002**: Compressed PLI < 100 bytes on the wire (well within the 225-byte LoRa budget).
- **SC-003**: Mixed-firmware mesh (2.7.x + 2.8.0+) maintains PLI and GeoChat across Apple ↔ Android via V1 ATAK_PLUGIN. Shape / marker / route exchange between two Apple peers on 2.7.x radios works via V1 ATAK_FORWARDER.
- **SC-004**: TAK server maintains TAK-client connections for 30+ minutes with iPhone screen off (BLE-peripheral background mode + keepalives).
- **SC-005**: Route CoT events on the receive path produce a saved KML data package in `Documents/TAK Routes/` and a "Route Received" notification within 2 seconds of mesh receive.
- **SC-006**: Swift Testing suite (~172 `@Test` methods across 8 TAK-related files) passes; new tests added for each FR.
- **SC-007**: SDK version pin in `Meshtastic.xcworkspace/.../Package.resolved` matches the latest tagged release of `meshtastic/TAKPacket-SDK` within one release cycle of the Android `core/proto/build.gradle.kts` bump.

## Assumptions

- All TAK logic lives in `Meshtastic/Helpers/TAK/` and `Meshtastic/Accessory/Accessory Manager/AccessoryManager+TAK.swift`; the bridge is the single entry point for both send paths.
- The connected radio's firmware version is available from the AccessoryManager's myNodeInfo metadata at send time.
- ATAK Civ and iTAK both support the standard TAK Server protocol (TLS on 8089, data package import).
- The TAKPacket-SDK is published as a Swift Package and pinned to a tagged release in `Package.resolved`.
- Zstd dictionaries are bundled inside the SDK; the Apple app does not train or load them directly.
- The 237-byte raw LoRa MTU is a hard limit; usable wire payload after Meshtastic framing is 225 bytes.
- Route data packages are written to the app's `Documents` directory and become visible in the Files app under On My iPhone → Meshtastic without any further permission grant.
- iOS Local Network entitlement is declared in the app's Info.plist; iOS auto-prompts on first inbound LAN connection.
- macOS Catalyst is a supported target; pure macOS (AppKit / non-Catalyst) is not.
- The V1 ATAK_FORWARDER path will NOT be backported to Android — it is preserved on Apple indefinitely for Apple-to-Apple legacy interop.
- Future TAK SDK features that require a higher firmware version should add a sibling property on `AccessoryManager` (alongside `supportsTAKv2`) with a clear cut-off so the bridge stays declarative.
