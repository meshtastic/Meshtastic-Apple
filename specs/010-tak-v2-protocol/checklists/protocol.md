# Protocol Integration Checklist: TAK v2 Protocol Integration (Apple)

**Purpose**: Validate Apple-side TAK v2 requirements quality, completeness, and clarity across all spec dimensions — three wire formats, NWListener lifecycle, SwiftUI surface, platform constraints, and cross-platform interoperability with Android.
**Created**: 2026-05-14
**Feature**: `specs/010-tak-v2-protocol/spec.md`
**Focus**: Full-breadth requirements quality | back-spec review gate | cross-platform parity coverage
**Depth**: Standard
**Audience**: Reviewer (cross-platform; Android maintainer in the loop)

---

## Constitution Compliance (Apple)

- [x] CHK001 — All TAK logic resides in `Meshtastic/Helpers/TAK/`, `AccessoryManager+TAK.swift`, and `Views/Settings/TAKServerConfig.swift` — no scattered TAK code outside these locations? [Consistency, Spec §Source-Set Impact]
- [x] CHK002 — Zero-lint-tolerance verified — `xcodebuild test` commands documented in `plan.md` § Constitution Check? [Consistency, Spec §Design Standards]
- [x] CHK003 — SwiftUI-only surface confirmed for the TAK config screen — no UIKit storyboards / AppKit imports? [Consistency, Spec §Architecture]
- [x] CHK004 — Privacy assessment confirms CoT payload content is never logged at non-debug levels (debug-only `Logger.tak.debug` logs are gated)? [Clarity, Spec §Privacy Assessment]
- [x] CHK005 — Design Standards review scoped to all TAK-surface views (`TAKServerConfig`, `TAKModuleConfig`, `TAKIdentitySection`, "Route Received" notification body)? [Completeness, Spec §Design Standards]
- [x] CHK006 — Verification commands documented for the full Apple TAK scope (test files + scheme) not just generic `xcodebuild build`? [Completeness, Spec §Plan Constitution Check]

## Requirement Completeness — Wire Protocol (V2 + V1 ATAK_PLUGIN + V1 ATAK_FORWARDER)

- [x] CHK007 — Apple's THREE wire formats explicitly enumerated (V2 port 78, V1 ATAK_PLUGIN port 72, V1 ATAK_FORWARDER port 257)? [Clarity, Spec §Summary, wire-protocol.md]
- [x] CHK008 — Wire byte budget (225 bytes after Meshtastic framing within 237-byte LoRa MTU) specified with the same arithmetic as Android? [Clarity, Spec §FR-001 NFR-001]
- [x] CHK009 — zstd dictionary selection (aircraft vs non-aircraft) documented as SDK-internal (vs. Android documenting the selection in app code)? [Completeness, research.md §R1]
- [x] CHK010 — `flags = 0xFF` (uncompressed TAK_TRACKER) handling documented for the receive path? [Coverage, wire-protocol.md §Flags Byte Encoding]
- [x] CHK011 — Apple's V1 ATAK_FORWARDER format (zlib + LT codes) documented in wire-protocol.md with the Apple-only interop caveat? [Gap, research.md §R6, wire-protocol.md]
- [x] CHK012 — V2 send "what happens when compression fails" specified — Apple throws `AccessoryError.ioFailed` from `sendCoTToMeshV2`; bridge logs and aborts? [Clarity, Spec §FR-004]
- [x] CHK013 — Port numbers (72, 78, 257) referenced via `PortNum.atakPlugin / atakPluginV2 / atakForwarder` enum constants throughout the implementation? [Clarity, wire-protocol.md §Port Assignments]
- [x] CHK014 — Behavior when V2 packet arrives on a v2-incapable firmware specified — Apple receives on all portnums regardless? [Coverage, Spec §FR-005]

## Requirement Completeness — Type Mapping

- [x] CHK015 — V2 CoT type coverage delegated to the SDK (vs. Android enumerating in app code) and Apple does not duplicate the type list? [Completeness, data-model.md §Enum Mappings]
- [x] CHK016 — Behavior for unknown CoT types on V2 documented — SDK parser throws; bridge logs and aborts (no fallback to V1)? [Clarity, Spec §Edge Cases]
- [x] CHK017 — V1 ATAK_FORWARDER classifier (`GenericCoTHandler.classifySendMethod`) outputs documented (`.takPacketPLI`, `.takPacketChat`, `.exiDirect`, `.exiFountain`)? [Completeness, data-model.md §V1 ATAK_FORWARDER Classification]
- [x] CHK018 — Bidirectional CoT preservation (source XML → V2 → wire → V2 → CoT XML → TAK client) maintains shape geometry via `sourceEventXml` preference? [Coverage, Spec §FR-011, research.md §R12]

## Requirement Completeness — Server Lifecycle (NWListener)

- [x] CHK019 — Failure modes beyond "port in use" documented — cert load failure, NWListener .failed state, TLS setup failure surface in `TAKServerManager.lastError`? [Coverage, Spec §Edge Cases]
- [x] CHK020 — Maximum concurrent client count specified — not bounded in `TAKServerManager` (practical limit set by `NWListener` defaults; document in tasks.md as a future hardening)? [Gap, tasks.md T100]
- [x] CHK021 — Graceful shutdown documented — `stop()` cancels keepalive tasks, closes connections via `NWConnection.cancel()`, removes from `connectedClients`? [Coverage, data-model.md §State Machines]
- [x] CHK022 — 10-second keepalive interval traceable to ATAK's 15-second `RX_STALE_SECONDS` with margin? [Clarity, Spec §FR-007, wire-protocol.md §Keepalive]
- [x] CHK023 — Behavior during iOS interruptions (incoming phone call, screen lock, app backgrounding) documented as bounded by BLE-peripheral background mode? [Gap, Spec §NFR-002, research.md]
- [x] CHK024 — Offline queue FIFO eviction at enqueue time (oldest evicted when 50-cap is hit) documented? [Clarity, Spec §FR-014, data-model.md §Offline Queue Entry]
- [x] CHK025 — Multiple-client-reconnect behavior — each client's `onClientConnected` triggers `drainOfflineQueue` independently; documented? [Coverage, data-model.md]

## Requirement Clarity — Legacy Fallback (Apple-only V1 ATAK_FORWARDER)

- [x] CHK026 — V1 ATAK_FORWARDER's Apple-to-Apple-only nature explicitly stated? Android peers act as opaque relays? [Clarity, Spec §Summary, wire-protocol.md §Interop Caveat]
- [x] CHK027 — `.exiDirect` vs `.exiFountain` decision rule documented — single fragment if zlib output fits one MTU; else LT-coded? [Completeness, data-model.md §V1 ATAK_FORWARDER Classification, contracts/wire-protocol.md]
- [x] CHK028 — Fountain receive timeout behavior documented — receiver waits for enough LT fragments to decode; drops silently on timeout? [Coverage, Spec §Edge Cases]
- [x] CHK029 — Why Apple keeps ATAK_FORWARDER while Android dropped it — documented with rationale in research.md §R6? [Completeness, research.md]

## Requirement Clarity — V1 ATAK_PLUGIN Interop with Android

- [x] CHK030 — Apple ↔ Android PLI / GeoChat interop on port 72 explicitly asserted in both `spec.md` and `wire-protocol.md`? [Clarity, Spec §Summary, wire-protocol.md §Port Assignments]
- [x] CHK031 — Bridging loss for non-PLI / non-GeoChat from Android-on-2.7.x to Apple-on-2.7.x documented (Android drops, Apple-only ATAK_FORWARDER doesn't help)? [Coverage, Spec §FR-012, Spec §Summary]

## Requirement Clarity — UI Surface (SwiftUI)

- [x] CHK032 — Combined identity-and-server settings screen documented as an Apple-specific UX choice (vs. Android's two-screen split)? [Clarity, Spec §Summary, research.md §R7]
- [x] CHK033 — `fileExporter` vs `fileImporter` use cases distinguished — exporter for data package, importer for custom `.p12`? [Clarity, quickstart.md, spec.md §FR-009]
- [x] CHK034 — `ZipDocument: FileDocument` and its `UTType.zip` typing called out? [Coverage, data-model.md / quickstart.md]
- [x] CHK035 — `TAKModuleConfig` (standalone) vs. `TAKIdentitySection` (embedded in `TAKServerConfig`) relationship documented — both backed by the same admin-message round-trips? [Coverage, Spec §Architecture]

## Requirement Clarity — Platform-Specific Behavior

- [x] CHK036 — No PARTIAL_WAKE_LOCK equivalent on iOS — reliability bounded by BLE-peripheral background mode? [Clarity, Spec §Apple-Specific UX Surface §Background Execution, research.md]
- [x] CHK037 — iOS Local Network permission — auto-prompted, no pre-flight UI? [Coverage, research.md §R10, Spec §Edge Cases]
- [x] CHK038 — `Documents/TAK Routes/` visibility in Files app under "On My iPhone → Meshtastic → TAK Routes" documented? [Clarity, Spec §Apple-Specific UX Surface §Files App Integration]
- [x] CHK039 — Mac Catalyst behavior called out (TAK server runs same NWListener path; macOS Finder for file access; macOS Notification Center for "Route Received")? [Coverage, Spec §Apple-Specific UX Surface §macOS]
- [x] CHK040 — Per-send V2 receive `Task.detached(priority: .utility)` justified — keeps `@MainActor` AccessoryManager dispatch loop responsive? [Clarity, Spec §FR-018, research.md §R8]

## Requirement Clarity — Route Receipt UX

- [x] CHK041 — "Route Received" notification body text — exact string documented for review? [Clarity, Spec §FR-008]
- [x] CHK042 — Route UID sanitization (`sanitizeForFilename`) defends against path traversal — documented with the exact stripped characters? [Coverage, Spec §FR-010]
- [x] CHK043 — KML manifest value escaping (`escapeXml`) prevents XML injection in route name — documented? [Coverage, Spec §FR-010]
- [x] CHK044 — Notification suppression / coalescing for rapid-succession route receipts — explicitly NOT implemented; flagged for backlog? [Gap, tasks.md T091]

## Cross-Platform Parity Gates

- [x] CHK045 — Apple SDK pin (`Meshtastic.xcworkspace/.../Package.resolved 0.2.3`) matches Android `core/proto/build.gradle.kts` SDK coord? [Consistency, research.md §R13]
- [x] CHK046 — Embedded `MeshtasticProtobufs/Package.resolved` pin discrepancy (currently `0.2.2`) called out as a known issue with a follow-up task? [Coverage, research.md §R13, tasks.md T080]
- [x] CHK047 — Wire-format equivalence on V2 explicitly asserted (Apple V2 wire bytes = Android V2 wire bytes)? [Clarity, wire-protocol.md §Port Assignments]
- [x] CHK048 — Cross-platform fixture suite work flagged for backlog (T082)? [Coverage, tasks.md]
- [x] CHK049 — Coordination requirement when SDK bumps documented in research.md (R13) and tasks.md (T122)? [Coverage]

## Verification

- [x] CHK050 — Spec verified against actual merged code as of 2026-05-14 (`HEAD = 72590684` on `main`; back-spec written on `spec-tak` branch)? [Consistency, plan.md]
- [x] CHK051 — Apple-specific test files enumerated (8 files, ~172 `@Test` methods) in plan.md and quickstart.md? [Completeness]
- [x] CHK052 — All FRs and NFRs have an identified code path / file location in plan.md? [Completeness]

---

## Notes

- This checklist mirrors the Android `checklists/protocol.md` structure but the items are scoped to Apple's surface area.
- Items marked complete reflect the back-spec status as of 2026-05-14; future SDK bumps or feature additions may unmark items for re-review.
- Cross-platform items (CHK045-CHK049) are the most likely to drift; consider adding to PR templates so they're re-checked on any TAK-touching PR on either repo.
