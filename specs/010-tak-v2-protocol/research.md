# Research: TAK v2 Protocol Integration (Apple)

**Status**: Complete (retroactive — documents decisions made across the V1 ATAK_FORWARDER era, the V2 cutover, and the issue-#6 SDK refactor).

This document captures the technology decisions in the merged Apple TAK v2 implementation. Where a decision matches Android's, this file references the Android `research.md` rather than restating; where Apple diverges, the rationale lives here in full.

---

## R1: Zstd Compression Strategy for LoRa MTU

**Decision**: Identical to Android — use pre-trained zstd dictionaries via `meshtastic/TAKPacket-SDK` (SPM pin `0.2.3`) with a 1-byte flags header encoding dictionary ID.

**Cross-reference**: See [Android `research.md` R1](https://github.com/meshtastic/Meshtastic-Android/blob/main/specs/005-tak-v2-protocol/research.md#r1-zstd-compression-strategy-for-lora-mtu). Wire-format identical.

**Apple-side surface**: `MeshtasticTAK.TakCompressor().compressWithRemarksFallback(_:maxWireBytes:)` returns `Data?`; a `nil` return means the packet won't fit even after `<remarks>` strip. The Apple bridge translates `nil` into `AccessoryError.ioFailed(...)` so the caller's `do/catch` doesn't treat the drop as a successful send.

---

## R2: Platform Abstraction for Compression

**Decision**: Apple uses the SDK directly — no expect/actual abstraction needed. The SDK ships an iOS-compatible Swift Package that calls into a vendored zstd C library (no Kotlin/Native shim).

**Rationale**: Unlike Android which has to share a `TakV2Compressor` between JVM and iOS via expect/actual, Apple consumes the SDK's iOS klib (Kotlin/Native via the Swift bridging layer) directly. No platform stub is required.

**Implication**: Apple does NOT have an "uncompressed TAK_TRACKER mode" fallback path on the send side — compression always runs. On the receive side, the SDK's decompressor handles the `0xFF` flags byte (TAK_TRACKER firmware sends raw protobuf) so we still interop with those packets.

**Alternatives Considered**:
- Wrap the SDK with our own Swift facade: rejected — adds maintenance with no value; the SDK API is already Swift-idiomatic from `MeshtasticTAK.CotXmlParser` / `TakCompressor` / `CotXmlBuilder`.

---

## R3: CoT XML Processing Approach

**Decision**: Hand-written streaming parser (`CoTXMLParser`) for inbound CoT from TAK clients (V1 path + V2 enrichment context); SDK builders for V2 outbound serialization.

**Rationale**:
- Inbound TAK-client XML can contain ATAK-Civ / iTAK-specific bloat elements that the SDK parser doesn't tolerate. The hand-written `CoTXMLParser` is permissive — it round-trips unknown elements into `rawDetailXML` and preserves the source XML in `sourceEventXml`.
- Outbound V2: use `MeshtasticTAK.CotXmlParser` + `TakCompressor` because they're the wire-protocol owners. The strip-then-parse pattern in `sendCoTToMeshV2` removes 24 bloat patterns first (`stripNonEssentialElements`) so the SDK parser sees clean input.

**Alternatives Considered**:
- Use the SDK parser for both inbound and outbound: rejected — the SDK is strict about element shapes (it expects clean wire CoT, not the verbose ATAK-Civ / iTAK source XML).
- Use `XMLParser` (Foundation): used internally inside `CoTXMLParser`; the overall flow is a hand-written state machine on top of `XMLParser` callbacks for performance and to preserve raw inner-element XML.

---

## R4: TLS Server Architecture

**Decision**: `Network.framework` (`NWListener`, `NWConnection`, `NWProtocolTLS`) with mTLS — NOT JSSE.

**Rationale**:
- `Network.framework` is the Apple-recommended modern API for TCP/TLS servers. Replaces the older `CFNetwork` / `Stream` APIs with structured-concurrency-friendly callbacks.
- `sec_protocol_options_set_min_tls_protocol_version(_, .TLSv12)` enforces TLS 1.2+; client cert verification is set up via `sec_protocol_options_set_verify_block` on the TLS options.
- Per-connection serial queue (`DispatchQueue(label: "tak.server", qos: .userInitiated)`) prevents concurrent broadcast corruption without explicit mutexes.
- TCP-layer keepalive (`tcpOptions.enableKeepalive = true`, `keepaliveIdle = 60`) handles NAT mappings; app-layer 10-second ping CoT keeps ATAK / iTAK's `RX_STALE_SECONDS = 15` counter under threshold.

**Alternatives Considered**:
- `URLSession` / `URLProtocol`: client-side only; not a server library.
- Vapor / Hummingbird: heavyweight HTTP-server framework; we need raw TLS sockets, not HTTP.
- BSD socket APIs (`socket`, `bind`, `listen` with manual `Security.framework` SSLContext): explicitly deprecated by Apple; supplanted by `Network.framework`.
- Vendored Java JSSE port: nonsense on Apple platforms.

---

## R5: Version Gating Strategy

**Decision**: Same as Android — runtime firmware version check via `AccessoryManager.supportsTAKv2` (`checkIsVersionSupported(forVersion: "2.8.0")`), evaluated per-send.

**Cross-reference**: See [Android `research.md` R5](https://github.com/meshtastic/Meshtastic-Android/blob/main/specs/005-tak-v2-protocol/research.md#r5-version-gating-strategy). Same rationale, same per-send pattern, same handling of firmware OTA mid-session.

**Apple-side surface**: `AccessoryManager.supportsTAKv2` is a computed property on the singleton `AccessoryManager.shared`; the bridge calls it from inside `sendToMesh(_:clientInfo:)` (line 187 of `TAKMeshtasticBridge.swift`). When firmware is unknown (handshake not complete), the version check returns false → bridge defaults to V1 → safe.

---

## R6: Three-Format Wire Strategy (ATAK_FORWARDER on Apple)

**Decision**: Apple keeps the V1 ATAK_FORWARDER (port 257) path with zlib + Fountain (LT) codes indefinitely, even after the V2 cutover. The official Meshtastic Android app does not implement send or receive on this portnum.

**Context — what port 257 actually is**: per the upstream `meshtastic/protobufs` documentation, `ATAK_PLUGIN` (72) is the portnum for the **official Meshtastic ATAK plugin** (carrying the slim `TAKPacket` protobuf — PLI and GeoChat only), and `ATAK_PLUGIN_V2` (78) is its V2 successor. `ATAK_FORWARDER` (257) is defined for the third-party [paulmandal/atak-forwarder](https://github.com/paulmandal/atak-forwarder) Android plugin, which carries arbitrary CoT XML via `libcotshrink`. So port 257 is the conventional "arbitrary CoT XML" channel in the Meshtastic mesh, distinct from port 72's slim PLI/Chat subset.

**Rationale for preserving it on Apple**:
- Before V2 existed, Apple's TAK integration relied on port 257 for any CoT type other than PLI / GeoChat. This is the only legacy path for shape / marker / route CoT exchange when both peers are on firmware ≤ 2.7.x.
- The Apple `EXICodec` produces standard zlib (78 xx header) with a comment explicitly noting "for Android interoperability" — the implementation was designed to interop with whichever Android-side decoder lives on the same portnum (the paulmandal plugin, primarily; possibly other compatible implementations). The Meshtastic Android *app* itself does not implement decode for this portnum, but the firmware mesh router still relays the bytes hop-to-hop.
- Dropping ATAK_FORWARDER on Apple would regress Apple-to-Apple legacy users (who still exist in deployed fleets) without buying anything.
- The code paid its complexity cost years ago — `EXICodec`, `FountainCodec`, and `GenericCoTHandler` all exist, are tested, and aren't significantly maintained anymore.

**Trade-offs**:
- Three send formats on Apple (V1 ATAK_PLUGIN, V1 ATAK_FORWARDER, V2) vs. two on Android (V1 ATAK_PLUGIN, V2 only).
- Apple's `GenericCoTHandler.classifySendMethod(for:)` is the only place the multi-format dispatch lives; the bridge calls it once per V1 send.
- Fountain-coded payloads can take 2–6 LoRa packets to deliver; receiving Apple peers wait for enough fragments to decode (LT codes are erasure-tolerant).
- Wire-compatibility with paulmandal's `libcotshrink` is asserted by code comments but not currently exercised by an automated cross-codec test (see `tasks.md` T101-adjacent for a follow-up).

**Alternatives Considered**:
- Drop ATAK_FORWARDER entirely (match Meshtastic-Android): rejected — regresses Apple-to-Apple legacy users.
- Backport ATAK_FORWARDER send/receive into the Meshtastic-Android app: rejected — significant Kotlin codegen, no production demand for a sunset path, and the paulmandal plugin already exists as a parallel Android-side implementation for users who want this functionality.
- Custom Apple-only wire format for legacy chunked CoT: rejected — port 257 with `libcotshrink`-compatible framing is already a community convention; designing a new portnum would orphan the existing receive-side implementations.

---

## R7: Combined Identity + Server Settings Screen

**Decision**: Embed the firmware `ModuleConfig.TAKConfig` editor (`TAKIdentitySection`) inside the in-app TAK server settings screen (`TAKServerConfig`) instead of splitting across two navigation destinations.

**Rationale**:
- Android keeps the firmware module config and the in-app server config in separate screens (Module Configuration → TAK and Settings → TAK Server). Users have to navigate between two screens to set their team color (firmware module config) and toggle the server (app config).
- On Apple, both nav entry points (`Settings → Modules → TAK Server` and `Settings → TAK Server`) route to the combined `TAKServerConfig` screen. The user sees identity controls at the top and server controls below — one screen, one mental model.
- The standalone `TAKModuleConfig.swift` still exists (and is accessible) for users who navigate directly to it, but the primary entry point is the combined screen.

**Implementation note**: `TAKIdentitySection` calls `requestTakConfigIfNeeded()` on appear (which fires `AccessoryManager.requestTAKModuleConfig`) so first-time users see a populated team / role rather than a perma-spinner.

**Alternatives Considered**:
- Match Android's split: rejected — adds navigation friction; the team / role values are commonly tweaked when configuring the server for the first time.
- Move all server config to the firmware module config screen: rejected — server config is app-state (AppStorage), not firmware state; conflating them confuses the persistence model.

---

## R8: V2 Receive on a Detached Task

**Decision**: `handleATAKPluginV2Packet(_:)` immediately hops to `Task.detached(priority: .utility)` for decompression, XML build, and KML / zip generation. Notifications hop back to `MainActor` for `LocalNotificationManager`.

**Rationale**:
- `AccessoryManager` is `@MainActor`-isolated. Without a detach, zstd decompression + SDK XML build + regex cleanup + KML / zip generation + `Data.write(to:)` into `Documents/TAK Routes/` would all run on the main actor.
- A large route or shape used to freeze the UI for hundreds of milliseconds. Copilot flagged this as a UI hang risk, and the `AccessoryManager` dispatch loop would stall because every other portnum handler was `await`ing the same actor.
- `Task.detached` (not just `Task`) so we don't inherit `@MainActor` from the enclosing `AccessoryManager` actor context.
- `priority: .utility` because this work is user-perceivable (a route should arrive promptly) but not latency-critical.

**Alternatives Considered**:
- Move `AccessoryManager` off the main actor: rejected — pervasive change touching every transport, requires re-auditing all `@Published` and SwiftData interactions.
- Dedicated `OperationQueue` for TAK work: rejected — single call site; over-abstracted.
- `DispatchQueue.global(qos: .utility).async { … }`: works, but `Task.detached` plays better with structured concurrency cancellation and the eventual `await MainActor.run { … }` for notifications.

---

## R9: Detail Stripping (24 patterns, Apple-side)

**Decision**: Strip 24 element / attribute patterns from outbound V2 CoT in `stripNonEssentialElements(_:)` — broader than Android's 16-element list.

**Rationale**:
- iTAK and ATAK Civ on iOS emit a different bloat element set than ATAK on Android. Patterns Apple strips that Android doesn't: `<voice>`, `<__geofence>`, `<__shapeExtras>`, `<creator>`, `<strokeStyle>`, attribute-level strips (`routetype=...`, `order=...`, `color=...`, `access=...`, empty `callsign=""`, empty `phone=""`), and UID strip on route waypoint `<link>` elements.
- The UID-strip on `<link point="..."/>` elements is the biggest single win: each route waypoint has a 36-char UUID that costs ~40 bytes on the wire, and the receiving TAK client derives its own UIDs anyway. Stripping recovers 40 × N bytes per route.
- Stripping before compression (not after) gives the zstd compressor cleaner input and smaller output.

**Apple-specific patterns vs. Android's 16**:

| Apple-only pattern | What it strips | Why iOS-specific |
|--------------------|----------------|------------------|
| `<voice[^>]*/>` | iTAK voice-chat state | Android ATAK doesn't emit this |
| `<__geofence[^>]*/>` | Geofence config metadata | ATAK Civ iOS-specific |
| `<__shapeExtras[^>]*/>` | Shape display extras | ATAK Civ iOS-specific |
| `<creator[^>]*/>` | Creator metadata block | Both emit, but Apple sees it more often |
| `<strokeStyle[^>]*/>` | Stroke style (SDK uses color fields) | Both, but Apple's version has more attributes |
| `routetype="..."` | Route display type label | iTAK / ATAK Civ |
| `order="..."` | Checkpoint order label | iTAK route waypoints |
| `color="..."` on link_attr | SDK uses strokeColor instead | iTAK overlay |
| `access="..."` | Access control attribute | iTAK |
| `callsign=""` | Empty callsign attribute | iTAK chat |
| `phone=""` | Empty phone attribute | iTAK contact |
| `uid="..."` on `<link point="..."/>` | Per-waypoint UUIDs | All — biggest single recovery |

**Alternatives Considered**:
- Use Android's 16-pattern list: rejected — leaves bloat on the wire that the Apple-side TAK clients regularly emit.
- Move strip logic into the SDK: considered for a future release; the strip is currently in `AccessoryManager+TAK.swift` to evolve independently of the SDK release cycle.
- Configurable strip list via Settings: over-engineered; patterns are stable.

---

## R10: iOS Local Network Permission (No Pre-Prompt)

**Decision**: Do not pre-request the Local Network entitlement; let iOS prompt the user on first inbound LAN connection attempt.

**Rationale**:
- iOS auto-prompts the user when an app first tries to bind to `0.0.0.0` or accept LAN connections. Pre-prompting requires using a `MultipeerConnectivity` or `Bonjour` discovery trick, which is opaque to users.
- The TAK server binds to all interfaces but ATAK / iTAK typically connect over `127.0.0.1` (when running on the same iPhone). Loopback doesn't require Local Network — so the user can use the app fully without granting Local Network unless they want LAN-side clients.
- When iTAK on iPad connects to Meshtastic on iPhone over Wi-Fi, iOS shows the standard "Allow [App] to find and connect to devices on your local network?" sheet; this is the expected UX.

**Implication**:
- No pre-flight permission state UI on Apple. The Server section just shows "Server running on 8089" and the user discovers Local Network requirement on the first off-device connection attempt.
- If Local Network is denied, iTAK / ATAK off-device clients fail to connect. There is no in-app explanation prompt currently — the user would need to find Settings → Meshtastic → Local Network to flip it on. (Documented in the in-app developer guide.)

**Alternatives Considered**:
- Pre-prompt via Bonjour discovery: rejected — gimmicky, surprises the user with a Wi-Fi permission prompt before they touch any networking feature.
- In-app explanation modal pointing at Settings → Local Network when the server starts: deferred (could be added later; current state matches the iOS default UX for similar apps).

---

## R11: Route Receipt Notification

**Decision**: Post a `UNUserNotification` titled "Route Received" (subtitle = route callsign, body = "Saved to Files → Meshtastic → TAK Routes. Open in iTAK to import.") when a `b-m-r` CoT generates a saved KML data package.

**Rationale**:
- iTAK silently ignores route CoT (`b-m-r`) received over its TCP streaming connection — known iTAK limitation.
- Without a notification, the user has no signal that a route arrived. They'd find the file in `Documents/TAK Routes/` only if they happened to open the Files app.
- A local notification (no server push, no permissions beyond the standard notification grant) lets the user know to switch to iTAK and import.
- The body text spells out the exact path so the user doesn't need to hunt for it.

**Apple-specific** (no Android equivalent currently). Android's KML files are written to `Documents/` (or the SAF-selected location) without a notification.

**Alternatives Considered**:
- In-app banner: rejected — only visible while Meshtastic is foreground; user is presumably switching to iTAK.
- Auto-import via Universal Links from Meshtastic → iTAK: blocked — iTAK doesn't currently expose a Universal Link for data package import; would require iTAK changes.
- Persistent badge on TAK Server tab: rejected — non-standard; badge semantics conflict with notification-count expectations.

---

## R12: Source Event XML vs. Re-serialized XML (V2 Outbound)

**Decision**: For V2 non-chat outbound, prefer `cotMessage.sourceEventXml` (the original XML from the TAK client) over `cotMessage.toXML()` (re-serialized from parsed fields). For chat (`b-t-f`), use `toXML()` because the bridge mutates the contact during enrichment.

**Rationale**:
- `toXML()` writes only the fields the `CoTMessage` struct knows about — it loses shape geometry (`<link point="..."/>` vertices), strokeColor / fillColor, and custom detail elements that the parser strips as "unknown."
- The SDK parser (`MeshtasticTAK.CotXmlParser`) handles the full element vocabulary including shape geometry. Feeding it the original XML preserves data that would otherwise be lost.
- For GeoChat (`b-t-f`), `sendToMesh` enriches the message with a synthesized `<contact callsign="...">` element (when iTAK / ATAK emit only `<__chat senderCallsign>`). The enrichment modifies the in-memory `CoTMessage` but doesn't write back to `sourceEventXml` — so we must use `toXML()` to pick up the synthesized contact.

**Code**:
```swift
let cotXml = (cotMessage.type != "b-t-f" ? cotMessage.sourceEventXml : nil)
    ?? enrichedMessage.toXML()
try await accessoryManager.sendCoTToMeshV2(cotXml, channel: channel)
```

**Alternatives Considered**:
- Always use `sourceEventXml`: rejected — loses chat enrichment.
- Always use `toXML()`: rejected — loses shape geometry.
- Add shape geometry fields to `CoTMessage` struct: deferred (the SDK is the source of truth for the full schema; mirroring it in the bridge struct is duplicative).

---

## R13: SDK Version Pinning (`0.2.3`)

**Decision**: Pin `TAKPacket-SDK` to `0.2.3` in `Meshtastic.xcworkspace/.../Package.resolved` (authoritative for the app target). The embedded `MeshtasticProtobufs/Package.resolved` is also pinned but at `0.2.2` (older state).

**Rationale**:
- `0.2.3` is the first SDK release where:
  - `SensorFov.range_m` is correctly typed as `Int?` (issue #5 in the SDK repo: the proto regen broke the Kotlin serializer, fix landed in `26dce30`).
  - The Android-side JAR strip strategy (issue #6) is wire-format-compatible with the Apple SDK consumption pattern (the strip only affects the Android JVM JAR, not the iOS klib).
- Pinning to a specific release (not a branch) ensures reproducible builds across CI / development machines.
- The workspace `.resolved` is the authoritative pin for the Meshtastic app target. The `MeshtasticProtobufs` package has its own `.resolved` because it's an embedded Swift Package — but when both are in the same workspace, the workspace pin wins for the app target.

**Discrepancy Note**: The embedded `MeshtasticProtobufs/Package.resolved` is at `0.2.2`. This is a known dependency-graph quirk — the embedded package resolves independently, but at build time the workspace pin (`0.2.3`) wins. Next SDK bump should sync both files in the same PR.

**Cross-repo SDK release coordination** (issue #6 sequel): when Android bumps its SDK coord (in `core/proto/build.gradle.kts`), Apple should bump `Package.resolved` to the same release tag in the same PR cycle to avoid wire-format drift.

---

## Cross-Reference

For wire-format details (flags byte encoding, compression algorithm, schema fields) see `contracts/wire-protocol.md`.

For Android decisions on the same topics (where they overlap) see [Android `research.md`](https://github.com/meshtastic/Meshtastic-Android/blob/main/specs/005-tak-v2-protocol/research.md).
