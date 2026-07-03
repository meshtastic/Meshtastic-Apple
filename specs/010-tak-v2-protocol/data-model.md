# Data Model: TAK v2 Protocol Integration (Apple)

Apple-side data model for TAK v2. Mirrors the Android `data-model.md` where the structures are equivalent (`CoTMessage`, the offline queue, the protocol selection state machine) and documents Apple-specific divergences (Swift value types, `NWEndpoint` references, SwiftData context, `LocalNotificationManager` interactions).

## Core Entities

### CoTMessage (Central Domain Model)

The Apple `CoTMessage` is a value type (`struct`) — Android's is a `data class` with the same semantics. Apple's `CoTMessage` is `Sendable` and `Identifiable`, with `id: UUID` for SwiftUI list diffing.

```swift
struct CoTMessage: Identifiable, Sendable {
    let id = UUID()

    // Core CoT event attributes
    var uid: String                 // Unique event ID (e.g., "ANDROID-device-uuid", "iOS-ABC123")
    var type: String                // CoT type string (e.g., "a-f-G-U-C", "b-t-f")
    var time: Date                  // Event creation time
    var start: Date                 // Event validity start
    var stale: Date                 // Event expiry time
    var how: String                 // How generated (e.g., "m-g", "h-e", "h-g-i-g-o")

    // Point element (location)
    var latitude: Double            // WGS84 latitude
    var longitude: Double           // WGS84 longitude
    var hae: Double                 // Height above ellipsoid (meters)
    var ce: Double                  // Circular error (meters)
    var le: Double                  // Linear error (meters)

    // Detail sub-elements
    var contact: CoTContact?        // <contact callsign="..." endpoint="..." phone="..."/>
    var group: CoTGroup?            // <__group name="Cyan" role="Team Member"/>
    var status: CoTStatus?          // <status battery="85"/>
    var track: CoTTrack?            // <track speed="..." course="..."/>
    var chat: CoTChat?              // <__chat ...> + <__group>
    var remarks: String?            // <remarks>...</remarks> free-text

    // Round-trip preservation
    var rawDetailXML: String?       // Preserved inner <detail> XML for V2 raw_detail fallback
    var sourceEventXml: String?     // Full source XML — preferred over toXML() for V2 non-chat
}
```

### Supporting Detail Models

```swift
struct CoTContact: Sendable, Equatable {
    var callsign: String
    var endpoint: String?
    var phone: String?
}

struct CoTGroup: Sendable, Equatable {
    var name: String                // Team color name (e.g., "Cyan", "Red", "Blue")
    var role: String                // Member role (e.g., "Team Member", "TeamLead", "HQ")
}

struct CoTStatus: Sendable, Equatable {
    var battery: Int                // 0–100 percent
}

struct CoTTrack: Sendable, Equatable {
    var speed: Double               // m/s
    var course: Double              // degrees
}

struct CoTChat: Sendable, Equatable {
    var chatroom: String?           // "All Chat Rooms" or recipient UID
    var id: String?                 // Chat ID
    var senderCallsign: String?     // Sender's callsign (fallback when <contact callsign> empty)
}
```

### TAKClientInfo

Tracks a connected TAK client's state. Apple-specific: holds an `NWEndpoint` reference so `TAKConnection` can surface the peer address in logs / UI.

```swift
struct TAKClientInfo: Identifiable, Sendable {
    let id = UUID()
    let endpoint: NWEndpoint        // Apple-only — Android uses a SocketAddress equivalent
    var callsign: String?           // Client's callsign (from first PLI)
    var uid: String?                // Client's self-reported UID
    let connectedAt: Date

    var displayName: String {
        callsign ?? uid ?? endpoint.debugDescription
    }
}
```

### TAKConnectionEvent

Per-connection event stream emitted by `TAKConnection`. Drives both the `TAKServerManager.connectedClients` published list and the routing decisions in `TAKMeshtasticBridge`.

```swift
enum TAKConnectionEvent: Sendable {
    case connected(TAKClientInfo)
    case clientInfoUpdated(TAKClientInfo)
    case message(CoTMessage, TAKClientInfo?)
    case disconnected
    case error(Error)
}
```

### TAKConnectionError

```swift
enum TAKConnectionError: LocalizedError {
    case connectionClosed
    case notConnected
    case encodingFailed
    case sendFailed(String)
}
```

### Chat Receipt Models (V2 GeoChat extension)

V2 GeoChat adds delivered / read receipts that ride in the GeoChat message body with an `ACK:D` / `ACK:R` prefix. The parsing helpers in `TAKMeshtasticBridge` cover both inbound and outbound:

```swift
extension TAKMeshtasticBridge {
    enum ReceiptType {
        case delivered  // "ACK:D"
        case read       // "ACK:R"
    }

    struct ParsedReceipt {
        let type: ReceiptType
        let messageId: String
    }
}
```

### Offline Queue Entry

`TAKServerManager` queues both parsed messages and raw XML so V2 shape / route / marker detail elements survive the round trip when no client is connected. The dual-variant queue is Apple-specific (Android's queue is `CoTMessage`-only at present).

```swift
private enum QueuedPayload {
    case message(CoTMessage)        // Parsed CoT — usable on V1 fallback path
    case rawXml(String)             // Raw V2 XML — preserves <link point>, colors, stroke
}

private struct QueuedMessage {
    let payload: QueuedPayload
    let enqueuedAt: Date
}
```

---

## Enum Mappings (V2 Path)

CoT type mappings are owned by the SDK (`MeshtasticTAK`); Apple does not maintain its own copy. The set is the same as Android's — see [Android `data-model.md` § Enum Mappings](https://github.com/meshtastic/Meshtastic-Android/blob/main/specs/005-tak-v2-protocol/data-model.md#enum-mappings) for the full table.

Apple-side gating: enum values arrive via `MeshtasticTAK.TakCompressor.decompress(_:)` returning a `TAKPacketV2` protobuf; `CotXmlBuilder.build(_:)` lifts them back to CoT XML for `TAKServerManager.broadcastRawXml(_:)`.

---

## V1 ATAK_FORWARDER Classification

`GenericCoTHandler.classifySendMethod(for:)` returns one of four enum cases when running on a firmware ≤ 2.7.x radio:

```swift
enum CoTSendMethod {
    case takPacketPLI              // → port 72, bare TAKPacket protobuf (official Meshtastic ATAK plugin's portnum)
    case takPacketChat             // → port 72, bare TAKPacket protobuf (official Meshtastic ATAK plugin's portnum)
    case exiDirect                 // → port 257, zlib-compressed CoT XML, single fragment
    case exiFountain               // → port 257, zlib-compressed CoT XML, LT-coded fragments
}
```

Classification rule of thumb: PLI (`a-*`) and chat (`b-t-f`) take the proto-only paths on port 72; everything else gets zlib-compressed onto port 257. If the compressed payload fits in a single LoRa MTU (~225 bytes after framing), `.exiDirect`; otherwise `.exiFountain` with Luby-Transform erasure codes spread across multiple packets.

Port 257 is `ATAK_FORWARDER`, originally defined for the third-party [paulmandal/atak-forwarder Android plugin](https://github.com/paulmandal/atak-forwarder) (encoded via `libcotshrink`). The Apple-side reimplementation uses standard zlib + Fountain framing and asserts Android interoperability in `EXICodec.swift` ("Uses standard zlib format (78 xx header) for Android interoperability"). The official Meshtastic Android app does NOT implement a receive handler for port 257 — Apple → official Meshtastic Android app traffic on this port surfaces nowhere; Apple → Apple works fully; Apple → Android-with-paulmandal-plugin is plausible but not currently verified by automated test.

---

## State Machines

### TAK Server Lifecycle

```
     ┌──────────┐
     │  STOPPED │ (toggle off)
     └────┬─────┘
          │ takServerEnabled didSet → true
          ▼
     ┌──────────┐
     │ STARTING │ (bind 8089, load certs from bundle / Keychain)
     └────┬─────┘
          │ NWListener.start completes; .ready state received
          ▼
     ┌──────────┐  newConnectionHandler  ┌─────────────────┐
     │ RUNNING  │ ◄────────────────────  │ CLIENT_CONNECTED│
     │(0 clients)│                       │(n clients)      │
     └────┬─────┘                        └────────┬────────┘
          │ takServerEnabled didSet → false       │ stop() / all disconnect / NWListener .failed
          ▼                                        ▼
     ┌──────────┐
     │  STOPPED │
     └──────────┘
```

### TAK Client Connection Lifecycle

```
     ┌──────────────┐
     │  CONNECTED   │ (NWConnection .ready, mTLS handshake complete)
     └──────┬───────┘
            │ first inbound PLI received → callsign extracted
            ▼
     ┌──────────────┐
     │  IDENTIFIED  │ (TAKClientInfo.callsign + uid populated)
     │  + KEEPALIVE │ (10s ping CoT task started)
     └──────┬───────┘
            │ NWConnection .cancelled / .failed / .waiting → timeout
            │ keepaliveTask cancelled, connection removed from TAKServerManager.connections
            ▼
     ┌──────────────┐
     │ DISCONNECTED │ (CoroutineScope ≈ Task cancelled; entry removed from connectedClients)
     └──────────────┘
```

### Protocol Version Selection (per-send)

```
     ┌─────────────────────────────┐
     │ CoT message from TAK client │
     │ (TAKMeshtasticBridge.sendToMesh)
     └──────────────┬──────────────┘
                    │
       ┌────────────▼─────────────┐
       │ accessoryManager.supportsTAKv2? │
       │ (= checkIsVersionSupported("2.8.0"))
       └────────────┬─────────────┘
              yes   │ no
                    ▼
          ┌─────────────────┐         ┌──────────────────────────────────┐
          │  V2 Path        │         │  V1 Dispatch                     │
          │  (port 78)      │         │  GenericCoTHandler.classifySend  │
          └────────┬────────┘         └──────────────┬───────────────────┘
                   │                                  │
                   ▼                                  ▼
          ┌─────────────────┐         ┌──────────────────────────────────┐
          │ sourceEventXml  │         │ .takPacketPLI / .takPacketChat   │
          │   ?? toXML()    │         │   → port 72, bare TAKPacket      │
          │ (non-chat       │         │ .exiDirect                       │
          │  prefers source │         │   → port 257, zlib + 1 frag       │
          │  for shape geom)│         │ .exiFountain                     │
          └────────┬────────┘         │   → port 257, zlib + LT frags    │
                   │                  └──────────────┬───────────────────┘
                   ▼                                 │
          ┌─────────────────┐                        │
          │ ensureMinimum   │                        │
          │ StaleForMesh    │                        │
          │ (15-min floor)  │                        │
          └────────┬────────┘                        │
                   ▼                                 │
          ┌─────────────────┐                        │
          │ stripNonEssent. │                        │
          │ Elements (24x)  │                        │
          └────────┬────────┘                        │
                   ▼                                 │
          ┌─────────────────┐                        │
          │ SDK CotXmlParser│                        │
          │ → TAKPacketV2   │                        │
          └────────┬────────┘                        │
                   ▼                                 │
          ┌──────────────────────────────┐           │
          │ TakCompressor                │           │
          │ .compressWithRemarksFallback │           │
          │ (maxWireBytes: 225)          │           │
          └────────┬────────┬────────────┘           │
                   │        │                        │
                   │ Data?  │ nil (overflow)         │
                   ▼        ▼                        │
          ┌────────────┐  ┌──────────────────┐       │
          │ port 78    │  │ throw AccessoryError      │
          │ send       │  │   .ioFailed             │
          └────────────┘  └──────────────────┘       │
                                                     ▼
                                          ┌──────────────────┐
                                          │ Apple-to-Apple   │
                                          │ legacy path      │
                                          │ (Android peers   │
                                          │  see opaque bytes)
                                          └──────────────────┘
```

### V2 Receive Pipeline (Detached Task)

```
     ┌────────────────────────────────┐
     │ MeshPacket arrives at          │
     │ AccessoryManager dispatch loop │
     │ (portnum = .atakPluginV2)      │
     └──────────────┬─────────────────┘
                    │
                    ▼  handleATAKPluginV2Packet(_:)
     ┌─────────────────────────────────┐
     │ Task.detached(priority: .utility)│
     │ (hop off @MainActor)             │
     └──────────────┬──────────────────┘
                    │
                    ▼
     ┌─────────────────────────────────┐
     │ TakCompressor.decompress(_:)    │
     └──────────────┬──────────────────┘
                    │
                    ▼
     ┌─────────────────────────────────┐
     │ CotXmlBuilder.build(packetV2)   │
     └──────────────┬──────────────────┘
                    │
                    ▼
     ┌─────────────────────────────────┐
     │ Strip <?xml ?> prologue         │
     │ Collapse > whitespace <         │
     └──────────────┬──────────────────┘
                    │
                    ▼
     ┌─────────────────────────────────┐
     │ TAKServerManager.broadcastRawXml│
     │   (preserves <link point>, colors)│
     └──────────────┬──────────────────┘
                    │
                    ▼ if route type ("b-m-r")
     ┌─────────────────────────────────┐
     │ RouteDataPackageGenerator       │
     │   .generateDataPackage           │
     │   .saveToDocuments               │
     └──────────────┬──────────────────┘
                    │
                    ▼ MainActor.run
     ┌─────────────────────────────────┐
     │ LocalNotificationManager        │
     │ schedules "Route Received"      │
     └─────────────────────────────────┘
```

---

## Validation Rules

| Field | Rule | Error Handling |
|-------|------|----------------|
| V2 compressed payload size | ≤ 225 bytes (`maxWirePayloadBytes`) | `compressWithRemarksFallback` returns `nil` → `sendCoTToMeshV2` throws `AccessoryError.ioFailed`; bridge logs and aborts send |
| V2 wire payload before flags byte | ≥ 2 bytes | `handleATAKPluginV2Packet` logs warning, returns |
| V1 ATAK_PLUGIN (port 72) PLI | Has `pli` or `chat` payload variant | Bridge logs "V1 send: failed to convert CoT to TAKPacket" and returns |
| V1 ATAK_FORWARDER (port 257) classify | `.exiDirect` / `.exiFountain` | Bridge logs "V1 send: EXI failed" and returns |
| CoT XML structure | Valid `<event>` root with `<point>` | `CoTXMLParser` returns nil; logs |
| Stale time | Must be ≥ now + 15 min for V2 outbound | `ensureMinimumStaleForMesh` rewrites the `stale` attribute and logs the adjustment |
| Offline queue | ≤ 50 messages, ≤ 5 min TTL | Oldest evicted on overflow; expired purged on drain |
| Port 8089 binding | Must succeed | `NWListener.start` failure → `TAKServerManager.lastError` populated, UI surfaces error |
| Route UID for filename | No path separators, no control chars, no `..` | `RouteDataPackageGenerator.sanitizeForFilename` rewrites or rejects |

---

## Wire Format (Apple)

See `contracts/wire-protocol.md` for the full wire-format contract. Brief summary here for parity with Android's `data-model.md`:

### TAKPacketV2 (Port 78)

```
┌─────────┬────────────────────────────────┐
│ Flags   │ Compressed TAKPacketV2 Protobuf │
│ (1 byte)│ (variable, ≤224 bytes)          │
└─────────┴────────────────────────────────┘

Flags byte:
  Bits 0-5: Dictionary ID (0 = non-aircraft, 1 = aircraft)
  Bits 6-7: Reserved
  0xFF: Uncompressed (raw protobuf follows, for TAK_TRACKER firmware)
```

### TAKPacket (Port 72, V1 ATAK_PLUGIN, Legacy)

```
┌──────────────────────────────┐
│ Raw TAKPacket Protobuf       │
│ (no compression, no header)  │
└──────────────────────────────┘
```

### V1 ATAK_FORWARDER (Port 257)

Port 257 was originally defined for the [paulmandal/atak-forwarder Android plugin](https://github.com/paulmandal/atak-forwarder); Apple reuses the same portnum for its own zlib + Fountain CoT-XML framing. The official Meshtastic Android app does not decode this port — see `contracts/wire-protocol.md` § Interop Caveat for the full receiver matrix.

```
Single-fragment (.exiDirect):
┌──────────────────────────────┐
│ zlib-compressed CoT XML       │
└──────────────────────────────┘

Multi-fragment (.exiFountain):
┌─────────────────────────┐ ┌─────────────────────────┐ ┌─────────────────────────┐ ...
│ LT(zlib(CoT XML)) frag 1 │ │ LT(zlib(CoT XML)) frag 2 │ │ LT(zlib(CoT XML)) frag N │
└─────────────────────────┘ └─────────────────────────┘ └─────────────────────────┘
```

---

## Key Constants

```swift
// TAKServerManager
static let defaultTLSPort = 8089
static let defaultTCPPort = 8087        // Legacy, not used

// V2 wire MTU
let maxWirePayloadBytes = 225            // Used in sendCoTToMeshV2

// Stale extension floor for V2 outbound
private static let minimumMeshStaleTTL: TimeInterval = 900   // 15 minutes

// Offline queue
private let offlineQueueTTL: TimeInterval = 5 * 60           // 5 minutes
private let offlineQueueMaxSize = 50

// Keepalive
private let keepaliveInterval: UInt64 = 10_000_000_000        // 10 seconds (nanoseconds)

// TCP layer
tcpOptions.enableKeepalive = true
tcpOptions.keepaliveIdle = 60                                 // 60-second TCP keepalive idle

// Capability gate
var supportsTAKv2: Bool { checkIsVersionSupported(forVersion: "2.8.0") }
```

---

## Persistent State

| Key | Type | Storage | Purpose |
|-----|------|---------|---------|
| `takServerEnabled` | `Bool` | `@AppStorage` (UserDefaults) | Toggle state; `didSet` triggers start/stop |
| `takServerChannel` | `Int` | `@AppStorage` | Mesh channel index used for V1 / V2 sends |
| `takServerReadOnly` | `Bool` | `@AppStorage` | Suppress outbound CoT (still receive) |
| `takServerMeshToCot` | `Bool` | `@AppStorage` | Bridge mesh telemetry into CoT (separate feature) |
| `tak.custom.server.p12.data` | `Data` | Keychain (via `TAKCertificateManager`) | User-imported server `.p12` cert |
| `tak.custom.client.p12.data` | `Data` | Keychain | User-imported client `.p12` cert |
| `Documents/TAK Routes/<uid>.zip` | File | App container `Documents/` | KML data package for iTAK route import |

---

## Cross-Reference

For wire-format details (flags byte encoding, compression algorithm, schema fields) see `contracts/wire-protocol.md`.

For design decisions and rationale (why three formats, why Network.framework, why detached Task, why 24 strip patterns) see `research.md`.

For Android-side parity (CoT type table, enum mappings) see [Android `data-model.md`](https://github.com/meshtastic/Meshtastic-Android/blob/main/specs/005-tak-v2-protocol/data-model.md).
