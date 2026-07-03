# Wire Protocol Contract: TAK v2 Protocol Integration (Apple)

## Overview

The Apple TAK integration encodes CoT (Cursor-on-Target) events using three wire formats over the Meshtastic LoRa mesh — one V2 format and two V1 formats. This contract documents the encoding, port assignment, and interoperability guarantees from the Apple side.

The V2 wire format is identical to Android's V2 format (defined by the SDK). The V1 ATAK_PLUGIN format (port 72) is also identical (interoperable with Meshtastic-Android). The V1 ATAK_FORWARDER format (port 257) was originally defined for the third-party [paulmandal/atak-forwarder Android plugin](https://github.com/paulmandal/atak-forwarder) (encoding: `libcotshrink`); the Apple Meshtastic app reuses the same portnum for arbitrary chunked CoT XML with its own zlib + Fountain framing. The official Meshtastic Android app does **not** implement a receive handler for port 257 — only the firmware mesh router forwards those bytes — so port 257 traffic from Apple is effectively visible only to (a) other Apple Meshtastic peers, or (b) anyone running the paulmandal plugin alongside the Meshtastic Android app (the wire-compatibility intent is asserted in `EXICodec.swift` comments but not currently verified by an automated test against `libcotshrink`).

---

## Port Assignments

| Port | Protobuf PortNum | Originally for | Apple Send | Apple Receive | Meshtastic-Android App |
|------|-----------------|----------------|-----------|---------------|------------------------|
| 72 | `ATAK_PLUGIN` | Official Meshtastic ATAK plugin | ✅ PLI + GeoChat on firmware < 2.8.0 | ✅ always | ✅ implements both directions |
| 78 | `ATAK_PLUGIN_V2` | Official Meshtastic ATAK plugin (v2) | ✅ all CoT on firmware ≥ 2.8.0 | ✅ always | ✅ implements both directions |
| 257 | `ATAK_FORWARDER` | paulmandal `atak-forwarder` Android plugin (libcotshrink) | ✅ non-PLI / non-GeoChat on firmware < 2.8.0 (Apple's own zlib + Fountain framing) | ✅ always | ❌ no receive handler; firmware mesh router forwards bytes only |

---

## TAKPacketV2 Wire Format (Port 78)

### Byte Layout

```
Offset  Size    Field
0       1       Flags byte
1       N       Payload (zstd-compressed or raw TAKPacketV2 protobuf)

Total: 1 + N bytes, where (1 + N) ≤ 225 bytes (maxWirePayloadBytes)
```

### Flags Byte Encoding

| Value | Meaning |
|-------|---------|
| 0x00 | Compressed with non-aircraft dictionary (ID 0) |
| 0x01 | Compressed with aircraft dictionary (ID 1) |
| 0x02-0xFE | Reserved for future dictionaries |
| 0xFF | Uncompressed raw TAKPacketV2 protobuf (TAK_TRACKER firmware) — Apple receives these via the SDK's decompress entry point |

### Compression

- **Algorithm**: zstd (Zstandard) with pre-trained dictionaries — same dictionaries as Android (shipped inside the SDK).
- **Dictionary selection**: based on CoT type — aircraft types (`a-*-A-*`) use dict 1, all others use dict 0. Selection happens inside `MeshtasticTAK.TakCompressor.compress(_:)` — Apple does not see the dictionary ID at the call site.
- **Library**: `MeshtasticTAK` Swift Package (vendored zstd C library inside the SDK; no zstd-jni equivalent on Apple).
- **Apple compress API**: `MeshtasticTAK.TakCompressor().compressWithRemarksFallback(_:maxWireBytes:) throws -> Data?` — returns `nil` if even remarks-stripped payload exceeds the wire limit. The Apple bridge translates `nil` to `AccessoryError.ioFailed`.
- **Apple decompress API**: `MeshtasticTAK.TakCompressor().decompress(_:) throws -> TAKPacketV2`.
- **Max decompressed size**: enforced by the SDK; Apple does not configure a separate limit.

### TAKPacketV2 Protobuf Schema

Schema is defined upstream in `meshtastic/protobufs`. Apple consumes the generated bindings via the `MeshtasticTAK` package (Kotlin/Native Swift export). Key payload variant names match Android:

| Payload Variant | CoT Types Covered |
|-----------------|-------------------|
| `pli` | All `a-*` position reports |
| `chat` | `b-t-f` GeoChat (with optional ACK:D / ACK:R receipt prefix) |
| `aircraft` | `a-*-A-*` aircraft (uses aircraft dictionary) |
| `shape` | DrawnShape kinds (circle, ellipse, freeform, polygon, rectangle, telestration) |
| `marker` | Marker kinds (spot, waypoint, named markers) |
| `route` | `b-m-r` route waypoints |
| `casevac` | `b-r-f-h-c` |
| `emergency` | `b-a-o-pan` |
| `task` | `b-i-v` |
| `rab` | Range-and-bearing |
| `raw_detail` | Fallback for unrecognized types (preserves inner `<detail>` bytes) |

#### Apple Send-Path Pipeline

```
CoTMessage (from TAK client)
  ↓ sourceEventXml ?? toXML()
Raw CoT XML
  ↓ ensureMinimumStaleForMesh(_:)        ← 15-min stale floor
  ↓ stripNonEssentialElements(_:)         ← 24-pattern strip
Stripped CoT XML
  ↓ MeshtasticTAK.CotXmlParser.parse(_:)
TAKPacketV2 protobuf
  ↓ TakCompressor.compressWithRemarksFallback(_:maxWireBytes: 225)
Data (flags byte + zstd protobuf)
  ↓ sendTAKV2Packet(_:channel:)
MeshPacket on port 78
```

#### Apple Receive-Path Pipeline

```
MeshPacket on port 78
  ↓ handleATAKPluginV2Packet(_:)
  ↓ Task.detached(priority: .utility)     ← hop off @MainActor
Data (flags byte + zstd protobuf)
  ↓ TakCompressor.decompress(_:)
TAKPacketV2 protobuf
  ↓ CotXmlBuilder.build(_:)
Rebuilt CoT XML
  ↓ strip <?xml ?> prologue + collapse > whitespace <
Forwardable CoT XML
  ↓ TAKServerManager.shared.broadcastRawXml(_:)   ← preserves shape detail
TAK client TCP stream
  ↓ (if type == "b-m-r")
RouteDataPackageGenerator.generateDataPackage + saveToDocuments
  ↓
Documents/TAK Routes/<sanitizedUid>.zip
  ↓ MainActor.run
LocalNotificationManager "Route Received" notification
```

---

## TAKPacket Wire Format (Port 72, V1 ATAK_PLUGIN, Legacy)

### Byte Layout

```
Offset  Size    Field
0       N       Raw TAKPacket protobuf (no header, no compression)
```

### Supported Payload Types (V1)

| Type | Apple Send | Apple Receive | Notes |
|------|-----------|---------------|-------|
| PLI (position) | ✅ | ✅ | Apple ↔ Android interop |
| GeoChat | ✅ | ✅ | Apple ↔ Android interop |
| Markers / Shapes / Routes | ❌ | ❌ | Not representable in V1 schema — falls through to V1 ATAK_FORWARDER on Apple |

### Apple Send Entry Point

`AccessoryManager+TAK.swift::sendTAKPacket(_:channel:)`:

```swift
func sendTAKPacket(_ takPacket: MeshtasticProtobufs.TAKPacket, channel: UInt32 = 0) async throws {
    // ...
    var dataMessage = DataMessage()
    dataMessage.portnum = .atakPlugin  // Port 72 (legacy V1)
    dataMessage.payload = try takPacket.serializedData()
    // ... build MeshPacket, set hopLimit, send via ToRadio
}
```

### Apple Receive Entry Point

`AccessoryManager+TAK.swift::handleATAKPluginPacket(_:)`:
- Decodes bare `TAKPacket` protobuf via `MeshtasticProtobufs.TAKPacket(serializedData:)`.
- Converts PLI / chat variants to `CoTMessage` (via `CoTMessage.init(takPacket:)`).
- Forwards to TAK clients via `TAKServerManager.shared.broadcast(_:)`.

---

## V1 ATAK_FORWARDER Wire Format (Port 257, Apple-only)

### Byte Layout (Single Fragment — `.exiDirect`)

```
Offset  Size    Field
0       N       zlib-compressed CoT XML (no Fountain framing)
```

### Byte Layout (Multi-Fragment — `.exiFountain`)

Multiple LoRa packets, each containing a Luby-Transform (LT) erasure-code fragment of the zlib-compressed CoT XML. Fragments include the LT codec's own framing (block size, seed, payload).

```
Per-packet:
Offset  Size    Field
0       4       LT header (block size + seed)
4       M       LT-coded fragment of zlib(CoT XML)
```

### Apple Send Entry Point

`Meshtastic/Helpers/TAK/GenericCoTHandler.swift::sendGenericCoT(_:channel:)`:
- Calls `EXICodec.encode(cotXml)` to zlib-compress.
- If the result fits in one LoRa MTU (~225 bytes after Meshtastic framing) → `.exiDirect`: single packet on port 257.
- Otherwise → `.exiFountain`: `FountainCodec.encode(_:)` produces N+M LT fragments (where N is the minimum needed to decode and M is the redundancy budget); each fragment is sent as a separate MeshPacket on port 257.

### Apple Receive Entry Point

`AccessoryManager+TAK.swift::handleATAKForwarderPacket(_:)`:
- Hands off to `GenericCoTHandler.handleIncomingForwarderPacket(_:)`.
- Maintains a per-source-uid buffer of incoming fragments.
- Once enough LT fragments accumulate (decoder reaches steady state), `FountainCodec.decode(_:)` produces the original zlib stream.
- `EXICodec.decode(_:)` reconstitutes the CoT XML.
- Forwards via `TAKServerManager.shared.broadcastRawXml(_:)`.

### Interop Caveat

The **official Meshtastic Android app does not decode `ATAK_FORWARDER` packets**. They appear in `MeshPacket` traffic with `portnum: .atakForwarder` but `core/takserver` (Android-side) has no receive handler — the firmware's mesh router relays the bytes hop-to-hop, but no Android-side app code surfaces them to a connected ATAK client.

The portnum itself was originally defined for the third-party [paulmandal/atak-forwarder](https://github.com/paulmandal/atak-forwarder) Android plugin (encoded via `libcotshrink`). Apple's `EXICodec` header asserts wire-compatibility with that ecosystem ("Uses standard zlib format (78 xx header) for Android interoperability"), but the assertion is not currently exercised by an automated cross-codec test — interop with paulmandal's plugin is plausible but unverified.

Net effect:

- **Apple → Apple, same mesh**: full round trip. ATAK_FORWARDER fragments transit any Android relays as opaque bytes and reassemble correctly on the receiving Apple peer.
- **Apple → official Meshtastic Android app**: bytes reach the Android device but never surface to a TAK client.
- **Apple → Android running paulmandal/atak-forwarder plugin**: theoretically works if Apple's zlib + Fountain framing matches paulmandal's `libcotshrink` wire format; not currently verified by test.
- **Android → Apple (any direction)**: the official Meshtastic Android app does not send on port 257 at all, so the inverse case has no traffic to consider.

---

## TAK Server Protocol (Port 8089)

Apple uses the same TAK Server protocol as Android. Listener implementation differs but the wire bytes are identical.

### Transport

- **Protocol**: TCP with TLS 1.2+ (mTLS required)
- **Port**: 8089
- **Binding**: All interfaces (loopback + LAN)
- **TLS Library**: `Network.framework` `NWProtocolTLS` (vs. Android's `javax.net.ssl`)
- **Authentication**: Mutual TLS — server presents `server.p12`, client presents `client.p12`, both trust `ca.pem`. Certs are bundled in the app's Resources by default; users may import custom `.p12` via `TAKCertificateManager` (persisted in Keychain).
- **TCP Keepalive**: `tcpOptions.enableKeepalive = true`, `keepaliveIdle = 60` (seconds)

### Message Framing

CoT events are sent as complete XML documents over the TLS stream, framed by detecting the closing `</event>` tag. Apple's `TAKConnection` reads from the `NWConnection` `receive` callback and accumulates bytes into a framing buffer until a complete `<event>...</event>` is recognized.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<event version="2.0" uid="..." type="..." time="..." start="..." stale="..." how="...">
  <point lat="..." lon="..." hae="..." ce="..." le="..."/>
  <detail>
    <!-- Type-specific detail elements -->
  </detail>
</event>
```

**Apple-specific framing note**: Inbound XML from iTAK / ATAK Civ can include a `<?xml ?>` prologue per message. Apple's parser handles either prologue-present or prologue-absent.

**Apple-specific outbound note**: V2 receive rebuilds CoT XML via `MeshtasticTAK.CotXmlBuilder` which emits a prologue. The Apple receive handler strips the prologue and collapses inter-tag whitespace before forwarding via `broadcastRawXml(_:)` — leaking the prologue mid-stream tears down the iTAK / ATAK TCP streaming parser. The strip uses a permissive regex (`^\s*<\?xml[^>]*\?>`) so it works regardless of attribute order or quote style.

### Keepalive

- **Interval**: 10 seconds (`TAKConnection.keepaliveInterval = 10_000_000_000` ns)
- **Format**: Ping CoT event sent over the TCP stream by `TAKConnection.startKeepalive()`
- **Purpose**: Stay below ATAK's `RX_STALE_SECONDS = 15` threshold so the client doesn't mark the server stale.

### Read-Only Mode

`TAKServerManager.userReadOnlyMode` (AppStorage) suppresses outbound CoT from TAK clients to the mesh. Inbound mesh-to-client traffic continues. The bridge checks this flag in `sendToMesh` and short-circuits with a `Logger.tak.info("TAK Server in read-only mode: Ignoring message from TAK client")` log.

---

## Data Package Format (.zip)

### Connection Data Package

Exported via `TAKDataPackageGenerator.generateDataPackage()` for ATAK Civ / iTAK client configuration. UTType: `.zip`. Surfaced through SwiftUI's `fileExporter` modifier.

```
Meshtastic_TAK_Server.zip
├── meshtastic-server.pref    # ATAK / iTAK connection preferences (XML)
├── truststore.p12            # CA certificate for server verification
├── client.p12                # Client identity for mTLS
└── manifest.xml              # MissionPackageManifest v2
```

### Route Data Package

Generated on receiving end for iTAK route import. Saved to `Documents/TAK Routes/<sanitizedUid>.zip` and surfaced via a `LocalNotificationManager` "Route Received" notification.

```
{sanitized_route_uid}.zip
├── {sanitized_route_uid}.kml   # KML LineString with waypoints
└── manifest.xml                 # MissionPackageManifest v2
```

**UID sanitization**: `RouteDataPackageGenerator.sanitizeForFilename(_:)` strips path separators, control characters, and `..` sequences so user-controlled UIDs can't escape the `Documents/TAK Routes/` directory.

**XML escaping**: `escapeXml(_:)` separately escapes values before interpolation into the manifest's `value="..."` attribute (preventing manifest XML injection).

---

## Inbound Processing Rules (Apple)

| Source Port | Apple Local Firmware | Apple Action |
|-------------|---------------------|--------------|
| 78 (V2) | Any | Detach `Task.utility` → SDK decompress → `CotXmlBuilder.build` → strip prologue/whitespace → `broadcastRawXml` |
| 78 (V2) + route type (`b-m-r`) | Any | All of the above, plus `generateDataPackage` + `saveToDocuments` + "Route Received" notification |
| 72 (V1 ATAK_PLUGIN) | Any | Decode `TAKPacket` proto → `CoTMessage.init(takPacket:)` → `broadcast` |
| 257 (V1 ATAK_FORWARDER) | Any | Hand off to `GenericCoTHandler.handleIncomingForwarderPacket` → reassemble Fountain → zlib-decompress → `broadcastRawXml` |

---

## Outbound Processing Rules (Apple)

`TAKMeshtasticBridge.sendToMesh(_:clientInfo:)` is the single entry point.

| CoT Type | Apple Local Firmware ≥ 2.8.0 | Apple Local Firmware < 2.8.0 |
|----------|------------------------------|------------------------------|
| PLI (`a-*`) | V2 (port 78, compressed) | V1 ATAK_PLUGIN (port 72, raw `TAKPacket` proto) |
| GeoChat (`b-t-f`) | V2 (port 78, compressed) | V1 ATAK_PLUGIN (port 72, raw `TAKPacket` proto) |
| Marker (`b-m-p-*`) | V2 (port 78, compressed) | V1 ATAK_FORWARDER (port 257, zlib + optional LT) |
| Route (`b-m-r`) | V2 (port 78, compressed) | V1 ATAK_FORWARDER (port 257, zlib + optional LT) |
| Shape (`u-d-*`) | V2 (port 78, compressed) | V1 ATAK_FORWARDER (port 257, zlib + optional LT) |
| Casevac (`b-r-f-h-c`) | V2 (port 78, compressed) | V1 ATAK_FORWARDER (port 257, zlib + optional LT) |
| Emergency (`b-a-o-pan`) | V2 (port 78, compressed) | V1 ATAK_FORWARDER (port 257, zlib + optional LT) |
| Task (`b-i-v`) | V2 (port 78, compressed) | V1 ATAK_FORWARDER (port 257, zlib + optional LT) |
| Other / unknown | V2 (port 78, compressed; SDK may throw) | V1 ATAK_FORWARDER (port 257, zlib + optional LT) |

### Per-Send Fork Code

```swift
if accessoryManager.supportsTAKv2 {
    let cotXml = (cotMessage.type != "b-t-f" ? cotMessage.sourceEventXml : nil)
        ?? enrichedMessage.toXML()
    try await accessoryManager.sendCoTToMeshV2(cotXml, channel: channel)
} else {
    let sendMethod = GenericCoTHandler.shared.classifySendMethod(for: enrichedMessage)
    switch sendMethod {
    case .takPacketPLI, .takPacketChat:
        guard let pkt = convertToTAKPacket(cot: enrichedMessage) else { return }
        try await accessoryManager.sendTAKPacket(pkt, channel: channel)
    case .exiDirect, .exiFountain:
        try await GenericCoTHandler.shared.sendGenericCoT(enrichedMessage, channel: channel)
    }
}
```

### MTU Enforcement (V2)

- Max wire payload: `maxWirePayloadBytes = 225` bytes (after Meshtastic protobuf framing within the 237-byte LoRa MTU).
- `compressWithRemarksFallback` attempts full-detail compression. If the result exceeds 225 bytes, it retries with `<remarks>` stripped. If still over, returns `nil`.
- On `nil`: `sendCoTToMeshV2` throws `AccessoryError.ioFailed("TAK V2 payload exceeds LoRa wire size limit (225 bytes) even with remarks stripped")`.
- No fragmentation, no queueing of oversized packets.

### MTU Enforcement (V1 ATAK_PLUGIN)

- V1 PLI / GeoChat is bounded by the proto schema; in practice always fits. No explicit size check.

### MTU Enforcement (V1 ATAK_FORWARDER)

- Single fragment (`.exiDirect`): zlib-compressed CoT XML must fit one LoRa MTU. If not → `.exiFountain`.
- Multi-fragment (`.exiFountain`): unlimited size (within reason — receivers may time out if too many fragments are needed). Practical ceiling ~6 fragments.

---

## Hop-Limit Handling

V2 sends must set `meshPacket.hopLimit` to a non-zero value. The protobuf default of `0` is treated by the firmware as "already exhausted" and the packet is silently dropped before TX — the queueStatus comes back clean and the "Sent TAK V2 packet to mesh" log fires, but peers never hear it on the air.

Apple's `sendTAKV2Packet` uses `takBroadcastHopLimit(forDevice:)` which reads the LoRa config's `hop_limit` field with a 3-hop fallback when the config hasn't been received yet or is left at the protobuf default. V1 sends (both ATAK_PLUGIN and ATAK_FORWARDER) follow the same pattern.

---

## Test Coverage

Apple-side tests for the wire-format contract:

| Test File | Coverage |
|-----------|----------|
| `MeshtasticTests/TAKBridgeTests.swift` | `sendToMesh` fork logic, contact enrichment, callsign registration |
| `MeshtasticTests/TAKBridgeDetailedTests.swift` | `parseReceipt`, `parseDeviceCallsign`, `createSmuggledDeviceCallsign`, round-trips |
| `MeshtasticTests/TAKCodecTests.swift` | EXI / Fountain codec round-trips, fragment reassembly |
| `MeshtasticTests/CoTMessageTests.swift` | `CoTMessage.toXML` / `init(takPacket:)` round-trips |
| `MeshtasticTests/CoTMessageDetailedTests.swift` | Edge cases: malformed XML, missing fields, stale-time handling |
| `MeshtasticTests/CoTXMLParserTests.swift` | Streaming parser correctness on iTAK / ATAK Civ source XML |
| `MeshtasticTests/CoTExtensionTests.swift` | CoT type classification, helper extensions |
| `MeshtasticTests/GenericCoTHandlerTests.swift` | V1 `.exiDirect` / `.exiFountain` classification |

V2 wire-format round-trips (Apple ↔ Android) are not currently tested in-repo; planned via shared SDK fixtures in a future release.

---

## Cross-Reference

For the parallel Android contract, see [Meshtastic-Android `contracts/wire-protocol.md`](https://github.com/meshtastic/Meshtastic-Android/blob/main/specs/005-tak-v2-protocol/contracts/wire-protocol.md).

For the SDK that owns the V2 wire bytes, see [`meshtastic/TAKPacket-SDK`](https://github.com/meshtastic/TAKPacket-SDK).
