# Implementation Plan: TAK v2 Protocol Integration (Apple)

**Branch**: `spec-tak` | **Date**: 2026-05-14 | **Spec**: `specs/010-tak-v2-protocol/spec.md`
**Input**: Feature specification from `/specs/010-tak-v2-protocol/spec.md`
**Status**: Retroactive — documents the existing merged Apple TAK v2 implementation (`Meshtastic/Helpers/TAK/`, `Meshtastic/Accessory/Accessory Manager/AccessoryManager+TAK.swift`, `Meshtastic/Views/Settings/TAKServerConfig.swift`, ~7,000 LOC).
**Companion**: Meshtastic-Android [`specs/005-tak-v2-protocol/plan.md`](https://github.com/meshtastic/Meshtastic-Android/tree/main/specs/005-tak-v2-protocol).

## Summary

Documents the iOS / macOS Catalyst implementation of TAK v2 protocol support. Adds a third wire format on top of Android's two: the Apple-only V1 ATAK_FORWARDER (port 257) path with zlib + Fountain (LT) codes for non-PLI / non-GeoChat CoT between legacy Apple peers. The V2 path uses the same TAKPacket-SDK as Android — wire-format-identical, byte-for-byte — and the apps will interop on the V2 portnum (78) regardless of platform.

Apple-specific stack: `Network.framework` for the TLS listener (vs. Android's JSSE), SwiftUI for the entire UI surface (vs. Android's Compose Multiplatform), SwiftUI `fileExporter` / `fileImporter` for cert / data-package I/O (vs. Android's SAF), `LocalNotificationManager` for the route-receive UX (no Android equivalent in the current Android impl), and the iOS Files app for the user-facing `Documents/TAK Routes/` surface.

## Technical Context

**Language / Version**: Swift 5.9+, targeting iOS 17.5+, iPadOS 17.5+, macOS via Mac Catalyst (Catalyst 17.5+ / macOS 14.6+).
**Primary Dependencies**: TAKPacket-SDK (SPM, pinned `0.2.3`), MeshtasticProtobufs (Swift Package), CocoaMQTT, CoreBluetooth, Network.framework, SwiftData (for node lookups in the bridge), SwiftUI, OSLog (Logger.tak channel).
**Storage**: App Documents for route KML data packages (`Documents/TAK Routes/`); Keychain for custom `.p12` certificates (`TAKCertificateManager`); App bundle for default `.p12` and `.pref` resources; `@AppStorage` for `takServerEnabled`, `takServerChannel`, `takServerReadOnly`, `takServerMeshToCot`.
**Testing**: Swift Testing framework (`@Suite`, `@Test`); ~172 TAK-tagged `@Test` methods across `MeshtasticTests/{TAKBridgeTests,TAKBridgeDetailedTests,TAKCodecTests,CoTMessageTests,CoTMessageDetailedTests,CoTXMLParserTests,CoTExtensionTests,GenericCoTHandlerTests}.swift`.
**Target Platform**: iOS / iPadOS (primary), macOS via Mac Catalyst (secondary). Not supported: watchOS, tvOS, visionOS, pure AppKit macOS.
**Project Type**: iOS app with embedded Swift Packages (`MeshtasticProtobufs`).
**Performance Goals**: V2 send round-trip < 100ms (including SDK parse, zstd compress, mesh tx); V2 receive processing (zstd decompress + XML build + optional KML/zip write) MUST NOT block `@MainActor`.
**Constraints**: 225-byte usable LoRa wire payload (per FR-001); iOS Local Network prompt; no PARTIAL_WAKE_LOCK equivalent — reliability bounded by BLE-peripheral background mode lifetime.
**Scale / Scope**: Same CoT type coverage as Android (defined by the SDK); ~7,000 LOC in `Meshtastic/Helpers/TAK/` + `AccessoryManager+TAK.swift` + `TAKServerConfig.swift`; 3 wire formats (V2 + 2 V1 variants); 1 combined settings screen + 1 module-config screen.

## Constitution Check

*All Apple-side principles evaluated.*

- **I. Single-Source Wire Protocol**: ✅ V2 wire bytes are defined entirely by `TAKPacket-SDK`; Apple does not maintain its own copy of the V2 parser / builder / compressor. SDK pin lives in `Meshtastic.xcworkspace/.../Package.resolved` and `Meshtastic.xcodeproj/project.xcworkspace/.../Package.resolved` (both at `0.2.3`).
- **II. Zero Lint Tolerance**: ✅ Verification commands:
  ```bash
  xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 17' test
  ```
- **III. SwiftUI on Apple**: ✅ All TAK config UI is SwiftUI (`TAKServerConfig`, `TAKModuleConfig`, `TAKIdentitySection`). No UIKit storyboards or AppKit code.
- **IV. Privacy First**: ✅ No PII / location / crypto-key logging. CoT data stays local. SDK and Protobufs packages not modified.
- **V. Single Settings Surface**: ✅ Combined identity + server controls in `TAKServerConfig` rather than splitting across two screens. Both nav entry points (Module Configuration → TAK and Settings → TAK Server) route to the same destination.
- **VI. Verify Before Push**: ✅ Local verification:
  ```bash
  xcodebuild -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 17' build test
  gh pr checks
  ```

## Project Structure

### Documentation (this feature)

```text
specs/010-tak-v2-protocol/
├── plan.md              # This file
├── spec.md              # Functional specification (back-spec of merged state)
├── research.md          # Phase 0: Technology decisions and rationale
├── data-model.md        # Phase 1: Entity models and state machines
├── quickstart.md        # Phase 1: Developer onboarding guide
├── contracts/
│   └── wire-protocol.md # Wire protocol contract (companion to Android's)
├── checklists/
│   ├── requirements.md  # FR / NFR completion gate
│   └── protocol.md      # Wire-format and interop gate
└── tasks.md             # Phase 2 retrospective tasks (back-fill)
```

### Source Code (repository root)

```text
Meshtastic/
├── Helpers/TAK/
│   ├── TAKMeshtasticBridge.swift         # Per-send V1/V2 fork; main orchestrator (1462 LOC)
│   ├── TAKServerManager.swift            # NWListener lifecycle, offline queue (839 LOC)
│   ├── TAKConnection.swift               # Per-client NWConnection state machine + keepalive (550 LOC)
│   ├── TAKCertificateManager.swift       # .p12 loading + Keychain persistence + mTLS trust (788 LOC)
│   ├── CoTMessage.swift                  # Domain model + toXML() serialization (545 LOC)
│   ├── CoTXMLParser.swift                # Streaming XML → CoTMessage (333 LOC)
│   ├── EXICodec.swift                    # V1 ATAK_FORWARDER zlib path (148 LOC)
│   ├── FountainCodec.swift               # V1 ATAK_FORWARDER LT-code fragmentation (627 LOC)
│   ├── GenericCoTHandler.swift           # V1 ATAK_FORWARDER classifier + dispatch (399 LOC)
│   ├── RouteDataPackageGenerator.swift   # b-m-r CoT → KML data package (262 LOC)
│   └── TAKDataPackageGenerator.swift     # Connection .zip generator (290 LOC)
│
├── Accessory/Accessory Manager/
│   ├── AccessoryManager.swift            # supportsTAKv2 property (line 860)
│   └── AccessoryManager+TAK.swift        # Send/receive handlers, dispatch (492 LOC)
│
├── Views/Settings/
│   ├── TAKServerConfig.swift             # Combined identity + server UI; ZipDocument; fileExporter (800 LOC)
│   └── Config/Module/
│       └── TAKModuleConfig.swift         # Standalone firmware module config (268 LOC)
│
└── Resources/docs/markdown/developer/
    └── tak-protocol.md                   # In-app developer guide (rendered via WKWebView)

MeshtasticTests/
├── TAKBridgeTests.swift                  # @Suite — bridge unit tests
├── TAKBridgeDetailedTests.swift          # @Suite — bridge edge cases (parseReceipt, smuggled UID, etc.)
├── TAKCodecTests.swift                   # @Suite — EXI / Fountain codec tests
├── CoTMessageTests.swift                 # @Suite — CoTMessage round-trip
├── CoTMessageDetailedTests.swift         # @Suite — CoTMessage edge cases
├── CoTXMLParserTests.swift               # @Suite — streaming parser tests
├── CoTExtensionTests.swift               # @Suite — CoT extension helpers
└── GenericCoTHandlerTests.swift          # @Suite — V1 classification tests

MeshtasticProtobufs/                      # Swift Package — generated protobuf bindings
└── Package.resolved                      # TAKPacket-SDK pin (currently 0.2.2 here, 0.2.3 in workspace)

Meshtastic.xcworkspace/xcshareddata/swiftpm/
└── Package.resolved                      # TAKPacket-SDK pin 0.2.3 (authoritative for app target)
```

**Structure Decision**: Single-target Xcode workspace. All TAK code lives in `Meshtastic/Helpers/TAK/`, `Meshtastic/Accessory/Accessory Manager/AccessoryManager+TAK.swift`, and `Meshtastic/Views/Settings/TAKServerConfig.swift`. The SDK is consumed as a Swift Package via SPM (separate from the embedded `MeshtasticProtobufs` package, which generates the firmware protobuf bindings).

## Phases (Retrospective)

This is a back-spec; the work is already merged. Phases below describe the historical sequence rather than future work.

### Phase 0: Legacy V1 Foundation (pre-2.8.0 firmware era)

- Bridge pattern (`TAKMeshtasticBridge.sendToMesh`)
- V1 ATAK_PLUGIN (port 72) send/receive for PLI / GeoChat
- V1 ATAK_FORWARDER (port 257) with EXI + Fountain for non-PLI/Chat CoT
- `TAKServerManager` with bundled `.p12` certs, NWListener mTLS on 8089
- `RouteDataPackageGenerator` (KML data packages for iTAK route import)
- `TAKDataPackageGenerator` (connection .zip for client config)

### Phase 1: V2 Protocol Integration

- Added `AccessoryManager.supportsTAKv2` capability check (firmware ≥ 2.8.0).
- Added `sendCoTToMeshV2` / `sendTAKV2Packet` / `handleATAKPluginV2Packet` in `AccessoryManager+TAK.swift`.
- Wired `TAKMeshtasticBridge.sendToMesh` to fork on `supportsTAKv2`.
- Integrated `TAKPacket-SDK` via SPM: `MeshtasticTAK.CotXmlParser`, `TakCompressor`, `CotXmlBuilder`.
- Added `stripNonEssentialElements` (24 patterns) and `ensureMinimumStaleForMesh` (15-min floor) to maximize V2 wire-payload fit.
- Pinned SDK to `0.2.3` in workspace `Package.resolved`.

### Phase 2: UX Refinements (combined identity surface)

- Merged the firmware `ModuleConfig.TAKConfig` editor into `TAKServerConfig` as `TAKIdentitySection`.
- Routed both Module Configuration → TAK and Settings → TAK Server nav entries to the same combined screen.
- Added `requestTakConfigIfNeeded()` on appear to populate first-time values without a perma-spinner.
- Standalone `TAKModuleConfig` retained for direct module-config navigation.

### Phase 3: Reliability & UX Polish

- `Task.detached(priority: .utility)` on V2 receive to keep `@MainActor` responsive on large routes.
- "Route Received" `LocalNotificationManager` toast on first KML data package save.
- Offline queue with `.message` and `.rawXml` variants (50-cap, 5-min TTL) in `TAKServerManager`.
- Hop-limit fix on V2 sends (`takBroadcastHopLimit(forDevice:)` with 3-hop fallback) to avoid silent firmware drop on `hop_limit=0`.

### Phase 4 (current): Cross-Repo Parity

- This back-spec.
- SDK ABI alignment via `TAKPacket-SDK` strip strategy (issues #5, #6 in the SDK repo).
- Future: shared cross-platform fixture suite consumed by both Apple and Android tests.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Three wire formats (V1, V1 ATAK_FORWARDER, V2) on Apple vs. two on Android | V1 ATAK_FORWARDER predates this spec and is the only path for shape / marker / route exchange between two Apple peers on firmware ≤ 2.7.x. Dropping it would regress Apple-to-Apple legacy users. | Dropping the V1 ATAK_FORWARDER path entirely was considered but rejected: legacy radios are still common in deployed fleets, and the Apple-side EXI + Fountain code paid its complexity cost years ago. |
| 24 strip patterns (Apple) vs. 16 (Android) | iTAK / ATAK Civ on iOS emit different bloat element sets than ATAK on Android — extra `<voice>`, `<__geofence>`, `<__shapeExtras>`, `<creator>`, `<strokeStyle>` patterns plus 6 attribute strips. Stripping more on Apple costs nothing on the wire but recovers 50-100 bytes per shape. | Sharing a single strip list with Android would either (a) over-strip on Android (no harm but no benefit) or (b) under-strip on Apple. Apple's superset matches the iOS-client behavior. |
| Inline `Task.detached` on V2 receive instead of a dedicated `OperationQueue` | One-call site; the V2 receive path is the only `@MainActor` hot path that does heavy CPU + filesystem work. A dedicated queue would add abstraction with no other callers. | An `OperationQueue` was considered but rejected — single call site, no priority interactions to manage. |
| Branch name `spec-tak` (no numeric prefix) | This branch is dedicated to writing the back-spec; the implementation is on `main`. The numbered `010-` directory is the spec convention; the branch convention is informal. | N/A — branch naming doesn't affect the artifact. |
| SDK pin discrepancy between `MeshtasticProtobufs/Package.resolved` (`0.2.2`) and `Meshtastic.xcworkspace/.../Package.resolved` (`0.2.3`) | Embedded Swift Packages resolve their own `Package.resolved` independently from the workspace; the workspace pin is authoritative for the app target. | Aligning them every release is a discipline issue; the next SDK bump should sync both. |
