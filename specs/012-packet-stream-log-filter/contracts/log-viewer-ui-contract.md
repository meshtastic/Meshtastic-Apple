# UI & Logging-Category Contract: Packet Stream Log Filter

This app has no external API. The relevant contracts are (a) the view/state behavior the log viewer exposes to the user, and (b) the logging-category semantics other code must honor after the audit.

## A. Filter sheet contract (`AppLogFilter`)

**Inputs (bindings):**
- `isPacketStreamOn: Bool` — NEW, top control.
- `categories: Set<Int>`, `levels: Set<Int>` — existing.
- `categoriesExpanded: Bool`, `levelsExpanded: Bool` — NEW accordion state.

**Behavioral guarantees:**
1. Packet Stream control renders **first/topmost**, above Categories and Log Levels (FR-001).
2. Active Packet Stream is clearly indicated (FR-010) and visually disables/dims the Categories and Log Levels groups (FR-002 override).
3. Categories and Log Levels are each a `DisclosureGroup` toggled independently (FR-005/FR-006).
4. Collapsing a group hides its rows and shrinks to header height (FR-007); expanding restores rows with selections intact (FR-008).
5. Selections in a collapsed group still apply when Packet Stream is OFF (FR-009).
6. Toggling accordions never mutates `categories`/`levels` (no selection loss — SC-004).

## B. Log viewer contract (`AppLog`)

**Mode: Packet Stream OFF (existing behavior preserved — FR-015)**
- `Table` of `OSLogEntryLog`, reverse-chronological, search, manual refresh, row → `LogDetail`, CSV export. Governed by `categories`/`levels`.

**Mode: Packet Stream ON**
1. Shows only Mesh-category entries, all levels (FR-002); ignores `categories`/`levels`.
2. Continuously appends new packets and keeps newest in view while pinned (FR-003/FR-020).
3. New entries revealed at ≤≈6/sec under load; immediate below threshold (FR-021/SC-008).
4. Retains ≤1,000 entries, dropping oldest (FR-011).
5. Empty/"waiting for packets" state when no traffic; populates on resume (FR-012).
6. Search still narrows the streamed entries (FR-013).
7. Scrolling away pauses auto-scroll; returning to bottom resumes (FR-023/SC-009).
8. Streaming pauses off-screen/backgrounded; resumes when active (FR-014).
9. Export/copy reflects what is shown, PII redacted for external readers (FR-024/SC-010).

## C. Logging-category contract (post-audit — binding on all app code)

Producers of log lines MUST use categories per these semantics (Constitution IV):

| Category | MUST contain | MUST NOT contain |
|----------|--------------|------------------|
| `Logger.mesh` (`🕸️ Mesh`) | Over-the-air packet events, inbound and outbound (text, position, telemetry, nodeinfo, routing, waypoint, etc.) | Config-received, admin/setup, persistence, serial debug |
| `Logger.radio` (`📟 Radio`) | Device serial/firmware debug output | Mesh packet events |
| `Logger.admin` (`🏛 Admin`) | Config/admin/setup message handling | Per-packet OTA events |
| `Logger.data` (`🗄️ Data`) | Persistence/save/parse events | Per-packet OTA events |
| `Logger.transport` (`🚚 Transport`) | Connection/handshake/link lifecycle | Packet sends (moved to `.mesh`) |

**Redaction invariant**: any field marked `privacy: .private`/`.private(mask: .none)` today MUST remain redacted after relocation. No `.private → .public` downgrades (FR-024).

**Acceptance hook**: with device serial logging ON, the Mesh category / Packet Stream contains 0 serial, config, admin-only, or persistence lines (SC-007).
