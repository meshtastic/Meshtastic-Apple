# Specification Quality Checklist: TAK v2 Protocol Integration (Apple)

**Purpose**: Validate the back-spec is complete and faithful to the merged Apple TAK v2 implementation before tagging the spec done.
**Created**: 2026-05-14
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No premature implementation details in the user-scenarios section (architecture is documented separately).
- [x] Focused on user value and observable behavior in the User Stories section.
- [x] Written so a non-iOS engineer (e.g., the Android maintainer) can review for parity.
- [x] All mandatory sections completed (Summary, Goals, Non-Goals, User Scenarios, Edge Cases, Architecture, Requirements, Source-Set Impact, Design Standards, Privacy, Success Criteria, Assumptions).

## Requirement Completeness

- [x] No `[NEEDS CLARIFICATION]` markers remain.
- [x] Requirements (FR-001 through FR-020) are testable and unambiguous.
- [x] Non-functional requirements (NFR-001 through NFR-005) are measurable.
- [x] Success criteria reference observable user-facing or wire-level outcomes (SC-001 through SC-007).
- [x] Success criteria are technology-agnostic where possible (wire bytes, byte sizes, time windows) — Apple-specific framework choices live in `research.md`.
- [x] All acceptance scenarios defined per user story.
- [x] Edge cases enumerated (zstd decompression failures, port-in-use, malformed XML, unknown CoT types, offline-queue overflow, Local Network denial, mac Catalyst, missing firmware version, partial Fountain delivery, iTAK route-receive silent-ignore).
- [x] Scope explicitly bounded (Non-Goals lists what we will NOT do).
- [x] Dependencies and assumptions identified (SDK version, firmware version, Local Network entitlement, Files app access).

## Feature Readiness

- [x] All functional requirements map to a code location in `plan.md`'s structure.
- [x] User scenarios cover the primary mesh-send, mesh-receive, mixed-firmware, lifecycle, identity-config, and dual-path flows.
- [x] Feature meets the success criteria documented in `spec.md`.
- [x] Architecture comparison with Android is explicit (table in `spec.md` § Architecture).

## Apple-Specific Coverage

- [x] iOS background-execution model documented (no PARTIAL_WAKE_LOCK equivalent; BLE-peripheral background mode noted).
- [x] iOS Local Network permission flow documented (auto-prompted; loopback works without).
- [x] iOS Files app integration documented (`Documents/TAK Routes/` user-visible).
- [x] SwiftUI surface explicitly called out (`fileExporter`, `fileImporter`, `FileDocument`, `LocalNotificationManager`).
- [x] Mac Catalyst support called out.
- [x] Swift Testing framework usage documented (not XCTest).
- [x] Network.framework usage documented (not JSSE).
- [x] V1 ATAK_FORWARDER (Apple-only) called out in three separate places (spec § Goals, plan § Phase 0, research § R6).

## Cross-Repo Parity

- [x] Companion to Android `specs/005-tak-v2-protocol` linked from every doc.
- [x] Wire-format equivalence with Android V2 explicitly asserted.
- [x] Wire-format divergence (Apple's V1 ATAK_FORWARDER) explicitly called out as Apple-only.
- [x] SDK pin version coordination requirement documented (FR-NFR-005, R13).
- [x] Cross-platform fixture parity work flagged in `tasks.md` (T082).

## Notes

- Spec is retroactive: implementation is merged on `main`; back-spec written 2026-05-14.
- All CoT types are owned by the SDK; this spec does not enumerate them inline. Cross-references to the SDK proto schema and Android `data-model.md` carry that information.
- Apple's three-wire-format reality is the largest deviation from Android's two-format spec; called out in every doc.
- Notification UX (route-received toast) is Apple-only with no Android equivalent — documented as such in `research.md` R11.
- The combined identity-and-server settings screen is an Apple-specific UX decision (`research.md` R7); Android keeps the two surfaces separate.
