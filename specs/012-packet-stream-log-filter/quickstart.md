# Quickstart: Verifying Packet Stream Log Filter

Manual + automated verification for the feature. Maps each check to spec requirements/criteria.

## Prerequisites

- App built from branch `012-packet-stream-log-filter` (Debug).
- A connected device on a mesh with traffic. For heavy load, use the `PerformanceSeedData` DEBUG harness or a busy channel; enabling serial debug logging on the device produces the Radio-category noise that proves the audit (SC-007).
- Log screen: Settings → Debug Logs (`AppLog`).

## Manual verification

### Live packet stream (US1)
1. Open the log filter; enable **Packet Stream** (top control). → Only Mesh packet entries show; Categories/Log Levels appear disabled. *(FR-001, FR-002, FR-010)*
2. Watch new packets append automatically, newest in view, within ~5s of occurring. *(FR-003, FR-020, SC-001)*
3. On a busy mesh, confirm entries flow at a readable pace (~6/sec), not a blur, and scrolling stays smooth. *(FR-021, SC-008, SC-005)*
4. Scroll up to read an older entry → flow pauses, no jump-to-bottom; scroll back to bottom → resumes. *(FR-023, SC-009)*
5. Disable Packet Stream → view returns to normal Table governed by Categories/Levels. *(FR-004, FR-015)*
6. Leave the screen / background the app and return → streaming resumes without manual refresh. *(FR-014, FR-006-task)*

### Trustworthy signal (US2)
7. Enable serial debug logging on the device. In Packet Stream / Mesh category, confirm **no** serial debug lines, **no** "config received", **no** admin-only lines, **no** DB save lines appear — only OTA packets. *(FR-016, FR-017, SC-007)*
8. Send a message from the app → the outgoing packet appears in the stream alongside incoming. *(FR-019)*
9. Switch to the Radio category → serial debug lines appear there; Admin → config/admin; Data → persistence. *(FR-018)*

### Accordions (US3) & placement (US4)
10. Open filter: collapse Categories and Log Levels → panel height drops ≥50%; selections preserved on re-expand. *(FR-005–FR-009, SC-003, SC-004)*
11. Confirm Packet Stream is the first control in the filter. *(FR-001, SC-002)*

### Empty + privacy
12. With no traffic, Packet Stream shows a "waiting for packets" state, not an error; populates when traffic resumes. *(FR-012)*
13. Export logs while a position packet is visible → open the export/Console: coordinates are redacted (`<private>`), not raw. *(FR-024, SC-010)*

## Automated tests

- `PacketStreamModelTests` (Swift Testing):
  - Reveal pacing never exceeds the per-second budget given a burst input.
  - `visibleEntries.count` never exceeds 1,000; oldest evicted first.
  - Incremental fetch since `lastSeenDate` yields only newer entries; boundary de-dup works.
  - Mesh-only predicate excludes other categories.
- `SwiftUIViewSnapshotTests`: `AppLogFilter` with Packet Stream off + sections collapsed, and Packet Stream on (groups disabled). Record references on a clean run.

## Audit safety check (reviewer)

- `grep` every `Logger.mesh.*` call site → each is an OTA packet event (no config/admin/persistence).
- `grep` outbound `Logger.transport.*` packet sends → moved to `.mesh`; connection/handshake stays `.transport`.
- Diff confirms no `privacy: .private` → `.public` change anywhere in the audit. *(FR-024)*
