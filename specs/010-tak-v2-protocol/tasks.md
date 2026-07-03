# Tasks: TAK v2 Protocol Integration (Apple)

This is a retrospective task list. The implementation is merged on `main`. Checked items reflect what's shipped; unchecked items are open work for follow-on parity with Android and improvements identified during the back-spec audit.

For the parallel Android tasks (which served as the structural reference for this spec), see [Meshtastic-Android `specs/005-tak-v2-protocol/tasks.md`](https://github.com/meshtastic/Meshtastic-Android/blob/main/specs/005-tak-v2-protocol/tasks.md).

---

## Phase 0 — Legacy V1 Foundation (Pre-2.8.0 Era)

- [x] **T001** Create `Meshtastic/Helpers/TAK/` directory and add the bridge skeleton.
- [x] **T002** Implement `CoTMessage` value type with `CoTContact`, `CoTGroup`, `CoTStatus`, `CoTTrack`, `CoTChat` sub-types.
- [x] **T003** Implement `CoTXMLParser` (Foundation `XMLParser`-based streaming parser).
- [x] **T004** Implement `TAKMeshtasticBridge.sendToMesh(_:clientInfo:)` with V1-only dispatch (port 72 + port 257).
- [x] **T005** Implement `TAKServerManager` with `NWListener` + `NWProtocolTLS` mTLS on port 8089.
- [x] **T006** Implement `TAKConnection` per-client state machine with framing buffer.
- [x] **T007** Implement `TAKCertificateManager` with bundled `.p12` cert loading and Keychain custom-cert persistence.
- [x] **T008** Implement `EXICodec` (zlib compress/decompress) and `FountainCodec` (LT erasure codes).
- [x] **T009** Implement `GenericCoTHandler.classifySendMethod(for:)` and `sendGenericCoT(_:channel:)`.
- [x] **T010** Implement `RouteDataPackageGenerator` (KML + manifest + zip; save to `Documents/TAK Routes/`).
- [x] **T011** Implement `TAKDataPackageGenerator` (`.p12` + `.pref` + manifest export zip).
- [x] **T012** Implement `TAKServerConfig` SwiftUI screen with toggle, cert mgmt, data package export.
- [x] **T013** Add `TAKModuleConfig` SwiftUI screen for firmware module config.
- [x] **T014** Add Swift Testing suites: `TAKBridgeTests`, `TAKBridgeDetailedTests`, `TAKCodecTests`, `CoTMessageTests`, `CoTMessageDetailedTests`, `CoTXMLParserTests`, `CoTExtensionTests`, `GenericCoTHandlerTests`.

---

## Phase 1 — V2 Protocol Integration

- [x] **T020** Add `TAKPacket-SDK` as Swift Package via SPM, pin in `Meshtastic.xcworkspace/.../Package.resolved`.
- [x] **T021** Add `AccessoryManager.supportsTAKv2` computed property (`checkIsVersionSupported(forVersion: "2.8.0")`).
- [x] **T022** Implement `AccessoryManager+TAK::sendTAKV2Packet(_:channel:)` with `portnum = .atakPluginV2`.
- [x] **T023** Implement `AccessoryManager+TAK::sendCoTToMeshV2(_:channel:)` with SDK `CotXmlParser` + `TakCompressor.compressWithRemarksFallback`.
- [x] **T024** Implement `AccessoryManager+TAK::handleATAKPluginV2Packet(_:)` with SDK `TakCompressor.decompress` + `CotXmlBuilder.build`.
- [x] **T025** Add `stripNonEssentialElements(_:)` with 24 element/attribute patterns (including UID strip on `<link point>` waypoints).
- [x] **T026** Add `ensureMinimumStaleForMesh(_:)` with 15-minute stale floor.
- [x] **T027** Wire V1/V2 fork in `TAKMeshtasticBridge.sendToMesh` on `accessoryManager.supportsTAKv2`.
- [x] **T028** Add `sourceEventXml` vs. `toXML()` preference: use source for non-chat V2 to preserve shape geometry.
- [x] **T029** Add GeoChat contact enrichment (synthesize `<contact callsign>` from `<__chat senderCallsign>` or `TAKClientInfo`).
- [x] **T030** Throw `AccessoryError.ioFailed` from `sendCoTToMeshV2` when `compressWithRemarksFallback` returns `nil` (don't silently drop).

---

## Phase 2 — UX Polish

- [x] **T040** Combine firmware module config (team/role) and in-app server config in one screen (`TAKServerConfig` + `TAKIdentitySection`).
- [x] **T041** Route both Settings → Modules → TAK Server and Settings → TAK Server nav entries to the same combined screen.
- [x] **T042** Add `requestTakConfigIfNeeded()` on `TAKIdentitySection.appear` to populate first-time values.
- [x] **T043** Implement SwiftUI `fileExporter` modifier on "Export Data Package" with `UTType.zip`.
- [x] **T044** Implement SwiftUI `fileImporter` modifier on "Import Custom Server Certificate" with `.p12` UTType.
- [x] **T045** Implement `ZipDocument: FileDocument` for the file exporter.
- [x] **T046** Add "Route Received" `LocalNotificationManager` notification with body "Saved to Files → Meshtastic → TAK Routes. Open in iTAK to import."
- [x] **T047** Primary channel warning section in `TAKServerConfig` when channel name conflicts with TAK chat-room semantics.

---

## Phase 3 — Reliability & Performance

- [x] **T050** Hop off `@MainActor` on V2 receive: `Task.detached(priority: .utility)` in `handleATAKPluginV2Packet`.
- [x] **T051** Add `MainActor.run` hop for `LocalNotificationManager` schedule in the detached task.
- [x] **T052** Add `takBroadcastHopLimit(forDevice:)` with 3-hop fallback for V2 sends (avoid firmware silent drop on `hop_limit = 0`).
- [x] **T053** Add TCP-layer keepalive on `NWListener` (`tcpOptions.enableKeepalive = true`, `keepaliveIdle = 60`).
- [x] **T054** Add per-connection 10-second app-layer ping CoT keepalive in `TAKConnection.startKeepalive`.
- [x] **T055** Add offline queue to `TAKServerManager` with `.message(CoTMessage)` and `.rawXml(String)` variants (50-cap, 5-min TTL).
- [x] **T056** Add `drainOfflineQueue()` on `onClientConnected` callback.
- [x] **T057** Add XML prologue + inter-tag whitespace strip on V2 receive (so SDK-emitted prologue doesn't tear down the TAK TCP parser mid-stream).

---

## Phase 4 — Cross-Repo Parity (this back-spec)

- [x] **T060** Write `specs/010-tak-v2-protocol/spec.md`.
- [x] **T061** Write `specs/010-tak-v2-protocol/plan.md`.
- [x] **T062** Write `specs/010-tak-v2-protocol/data-model.md`.
- [x] **T063** Write `specs/010-tak-v2-protocol/research.md`.
- [x] **T064** Write `specs/010-tak-v2-protocol/contracts/wire-protocol.md`.
- [x] **T065** Write `specs/010-tak-v2-protocol/quickstart.md`.
- [x] **T066** Write `specs/010-tak-v2-protocol/tasks.md` (this file).
- [x] **T067** Write `specs/010-tak-v2-protocol/checklists/requirements.md`.
- [x] **T068** Write `specs/010-tak-v2-protocol/checklists/protocol.md`.

---

## Open Work — Parity Backlog

These tasks are not yet shipped. They're items identified during the back-spec audit where Apple could match Android, or where the Apple surface has gaps worth closing.

### Parity Gaps

- [ ] **T080** Sync `MeshtasticProtobufs/Package.resolved` SDK pin (currently `0.2.2`) with `Meshtastic.xcworkspace/.../Package.resolved` (currently `0.2.3`). Track on next SDK bump.
- [ ] **T081** Add an in-app TAK test runner (parallel to Android's `TakMeshTestRunner`). Show per-CoT-type send / receive byte sizes and round-trip success.
- [ ] **T082** Add a shared cross-platform fixture suite (iOS + Android both consume the same CoT XML fixtures from the SDK repo) for V2 wire-format parity tests.
- [ ] **T083** Document the `MeshtasticProtobufs` Swift Package's role in the Apple build (it's separate from `MeshtasticTAK`, and that's not obvious from the file layout).

### UX Polish

- [ ] **T090** Surface a Local Network permission explanation when the server starts and no clients connect within N seconds (current UX requires the user to discover Settings → Local Network on their own).
- [ ] **T091** Add suppression / coalescing for "Route Received" notifications when multiple routes arrive in quick succession.
- [ ] **T092** Add an Apple-side equivalent of the Android primary-channel warning when the user's `takServerChannel` selection conflicts with a non-TAK channel.
- [ ] **T093** Surface SDK version in Settings → About so users can see the wire-protocol version their app is on.

### Reliability

- [ ] **T100** Add a unit test asserting that V2 receive doesn't block `@MainActor` for more than 50ms on a 200-waypoint route fixture.
- [ ] **T101** Add a unit test asserting that `compressWithRemarksFallback` returning `nil` produces `AccessoryError.ioFailed` (not a silent drop).
- [ ] **T102** Add an integration test exercising the offline queue across a simulated disconnect/reconnect cycle.
- [ ] **T103** Add a metric (or `Logger.tak.info` line) tracking V2 send / receive byte sizes per CoT type for field debugging.

### V1 ATAK_FORWARDER Sunset Planning (No Action Yet)

- [ ] **T110** Document an end-of-life plan for V1 ATAK_FORWARDER (port 257) once firmware ≤ 2.7.x deployment drops below a defined threshold. No work yet — preserve indefinitely.
- [ ] **T111** Add deprecation telemetry: count V1 ATAK_FORWARDER send/receive events to inform the EOL decision.
- [ ] **T112** Verify (or refute) wire-format interop with [paulmandal/atak-forwarder](https://github.com/paulmandal/atak-forwarder)'s `libcotshrink` encoding. `EXICodec.swift`'s header comment claims "for Android interoperability" but there's no automated test asserting bidirectional decode against a known-good `libcotshrink` fixture. Either confirm and document the interop guarantee, or downgrade the assertion to "Apple-to-Apple only" once and for all.

### Cross-Platform Protocol Evolution

- [ ] **T120** When the SDK adds a new CoT type, mirror the Android `tasks.md` change here (in `tasks.md` and `data-model.md`).
- [ ] **T121** When the SDK changes its dictionary set (e.g., adds a third dictionary for a new payload class), update `contracts/wire-protocol.md` flags-byte table on both sides.
- [ ] **T122** Set up a Renovate / Dependabot rule (or manual checklist) so the Apple SDK pin is bumped in the same release window as the Android coord. (Android already has its Renovate setup; mirror in `.github/renovate.json` here.)

---

## Out-of-Scope

These were considered and explicitly deferred. Not on the backlog above.

- ❌ Port the Android `KMP TAK module` directly to Apple (rejected — Apple is single-target Swift; KMP would introduce massive build complexity for one shared module).
- ❌ Backport V1 ATAK_FORWARDER to Android (rejected — significant Kotlin codegen, no production demand, increases Android binary size for a sunset path).
- ❌ Replace `Network.framework` with a third-party Swift TLS library (e.g., NIOSSL) (rejected — `Network.framework` is the Apple-recommended modern API and ships with the platform).
- ❌ Implement a TAK Server with mission sync / federation / enterprise features (out of scope; same as Android).
- ❌ Build a standalone in-app TAK client UI (out of scope; iTAK / ATAK remain the clients).
- ❌ Move TAK logic to a separate Swift Package within the workspace (current single-target layout works; modularization is a separate refactor concern).
