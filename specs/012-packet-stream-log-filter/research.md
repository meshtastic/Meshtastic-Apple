# Phase 0 Research: Packet Stream Log Filter

All open unknowns from the Technical Context are resolved below. Spec clarifications (Session 2026-06-02) already fixed: outbound→Mesh, override Mesh-only/all-levels, fixed ≈6/sec pacing, 1,000-entry cap, PII redaction preserved.

## R1 — How to live-tail the unified log store

**Decision**: Poll `OSLogStore(scope: .currentProcessIdentifier)` on a repeating timer (~1s) while the screen is active, advancing the read position from the **last-seen entry date** and appending only newer entries.

**Rationale**: OSLog exposes no push/subscription/notification API for new entries — the only read path is `OSLogStore.getEntries(at:matching:)`. The current `Logger.fetch` always starts at `store.position(timeIntervalSinceLatestBoot: 0)` and walks the entire store on every call ([Logger.swift:52](../../Meshtastic/Extensions/Logger.swift#L52)); doing that on a 1s loop would re-scan the whole boot-to-now store repeatedly and get more expensive over time. Advancing via `store.position(date: lastSeenDate)` bounds each poll to the newly arrived slice. A ~1s poll comfortably meets SC-001's ≤5s visibility.

**Implementation note**: add an incremental variant, e.g. `Logger.fetch(predicateFormat:since:)` taking an optional `Date`; when `since` is provided use `store.position(date:)`, else preserve today's boot-position behavior. De-dup on the boundary second by tracking the last entry identity (date + composedMessage hash) since `date:` positioning is second-granular.

**Alternatives considered**:
- *Re-scan from boot each tick* — simple but O(store) per poll, degrades on long sessions. Rejected.
- *Tap the app's own packet pipeline directly* (observe `processFromRadio`) instead of OSLog — would be truly live but bypasses the log viewer's existing model, duplicates the data path, and wouldn't reflect what export/Console shows. Rejected: keep one source of truth (the log store) consistent with the rest of the viewer.

## R2 — Pacing the reveal rate (≈6 entries/sec)

**Decision**: Two-stage buffer. Poll appends new entries to a *pending* queue; a display ticker (`Task` with `Task.sleep`, ~167ms cadence or a small batch per tick) moves entries from pending → visible at ≤6/sec. Below the threshold, entries pass straight through.

**Rationale**: Satisfies FR-021/SC-008 (legible flow) and FR-022 (pacing throttles *display*, not ingestion). Decoupling ingest from reveal means a burst doesn't freeze the UI; the pending queue is itself bounded (see R3).

**Alternatives considered**:
- *Throttle the poll itself* — would drop or delay ingestion and lose the "counted while paced" guarantee (FR-022). Rejected.
- *Animate scroll speed instead of gating count* — harder to make legible and platform-inconsistent. Rejected.

## R3 — Bounded retention (1,000 entries) + overload

**Decision**: Visible buffer is a capped ring of 1,000 (`Array` with drop-oldest on append). The pending queue is also capped (e.g., 1,000); on sustained overload the oldest *pending* entries are dropped before they are ever revealed, and a subtle "stream is dropping entries" indication MAY be shown.

**Rationale**: FR-011 + FR-022. Bounds memory (SC-005) regardless of mesh load; favors most-recent traffic, which is what a live troubleshooter wants.

## R4 — Auto-scroll with read-pause

**Decision**: Track whether the view is "pinned to the live edge." New entries auto-scroll to bottom only while pinned. Scrolling away from the bottom unpins (pauses follow); returning to the bottom re-pins (resumes). Reuse the existing bottom-anchor + `ScrollViewReader` pattern already used in the message lists.

**Rationale**: FR-023/SC-009. Note: `AppLog` currently renders logs in a `Table` sorted reverse-chronological ([AppLog.swift:37](../../Meshtastic/Views/Settings/AppLog.swift#L37)). For the streaming mode a bottom-anchored chronological list (newest at bottom, flowing upward) reads more naturally as a "stream"; decision is to render the Packet Stream mode with a dedicated scrolling list while leaving the static `Table` for normal mode. (UI detail; confirm against design standards.)

## R5 — The Mesh-category audit (making Mesh = packets only)

**Decision**: Reclassify log call sites so categories mean exactly one thing:
- **Keep on `.mesh`**: per-packet events from the inbound portnum dispatch in `processFromRadio` ([AccessoryManager.swift:589](../../Meshtastic/Accessory/Accessory%20Manager/AccessoryManager.swift#L589)) — text, position, telemetry, nodeinfo, routing, waypoint, etc. — i.e., "a packet crossed the mesh."
- **Move to `.admin`**: config-received / module-config / admin-response / setup handshake lines currently on `.mesh` (e.g., in [MeshPackets.swift](../../Meshtastic/Helpers/MeshPackets.swift) and [UpdateSwiftData.swift](../../Meshtastic/Persistence/UpdateSwiftData.swift)).
- **Move to `.data`**: persistence/save lines (mostly already `.data` — verify none leak to `.mesh`).
- **Move outbound packet sends `.transport` → `.mesh`**: the `send(_:)` path ([AccessoryManager.swift:421](../../Meshtastic/Accessory/Accessory%20Manager/AccessoryManager.swift#L421)) and packet sends in `AccessoryManager+ToRadio.swift`, so both directions appear in the stream (FR-019). Keep genuinely transport-level lines (connect/handshake/link) on `.transport`.
- **Keep on `.radio`**: device serial/firmware logs in `didReceiveLog` ([AccessoryManager.swift:514](../../Meshtastic/Accessory/Accessory%20Manager/AccessoryManager.swift#L514)) — never `.mesh`.

**Rationale**: FR-016/017/018/019. Constitution Principle IV is satisfied/strengthened. No new category needed (keeps the filter's `LogCategories` enum stable and avoids a fourth concept; decision over a dedicated `.packet` category).

**Audit method**: enumerate every `Logger.mesh.*` and outbound `Logger.transport.*` call site, classify each as packet vs non-packet, and relocate. This is mechanical and behavior-preserving except for the category label. Each moved line keeps its existing `privacy:` markers verbatim (R6).

**Alternatives considered**:
- *New `Logger.packet` category* — cleaner semantically but adds a filter entry, a new constitution category, and still requires moving the non-packet lines off `.mesh`. The user chose to audit and reuse Mesh. Rejected.

## R6 — Preserving PII redaction

**Decision**: The audit relocates call sites verbatim including their `privacy:` interpolation markers; no field currently `.private` becomes `.public`. Coordinate-bearing lines (position packets, serial GPS) keep `.private` / `.private(mask: .none)` exactly as today ([AccessoryManager.swift:523](../../Meshtastic/Accessory/Accessory%20Manager/AccessoryManager.swift#L523), [LocationsHandler.swift:248](../../Meshtastic/Helpers/LocationsHandler.swift#L248)).

**Rationale**: FR-024/SC-010. The in-app viewer reads the current process's own store, so it can display the device's own data on-screen; redaction protects exported/shared logs and external tools (Console, sysdiagnose). A review checklist item verifies no downgrade slipped in during the move.

## R7 — Filter accordions

**Decision**: Replace the two always-expanded `Section`s in [AppLogFilter.swift](../../Meshtastic/Views/Settings/Logs/AppLogFilter.swift) with collapsible `DisclosureGroup`s (bound `@State` expand/collapse per section). Add a Packet Stream row/toggle as the first control above both groups. When Packet Stream is on, the two groups are disabled/dimmed (override per clarification). Default: Packet Stream off; sections default compact (Categories collapsed by default to shrink the panel; tune against design standards).

**Rationale**: FR-005–FR-009, FR-001, FR-010; SC-003 (≥50% height reduction when collapsed). `DisclosureGroup` preserves selections in collapsed sections automatically since the binding state is unchanged (FR-008/FR-009).

## Resolved unknowns summary

| Unknown | Resolution |
|---------|-----------|
| Live update mechanism | Poll OSLogStore incrementally from last-seen date (R1) |
| Readable pacing | Two-stage buffer, ticker reveals ≤6/sec (R2) |
| Memory bound / overload | Capped visible + pending buffers, drop oldest (R3) |
| Auto-scroll/pause | Pin-to-live-edge tracking (R4) |
| Packet signal source | Audit + reuse Mesh; outbound moved from Transport (R5) |
| PII | Preserve `privacy:` markers verbatim (R6) |
| Accordion UI | DisclosureGroups + top Packet Stream toggle (R7) |

## Design standards review (T001 / T026, v1.4)

Reviewed against Meshtastic Client Design Standards v1.4 (the `_latest` pointer resolves to `v1_4.md`). Findings for the filter + stream UI:

- **List rows neutral** (checklist): stream rows color the *text* by log level (matching the existing log Table), not the row background. ✓ consistent with the existing log view.
- **Native patterns / empty state**: native `Toggle`, `Form`/`Section`, `ContentUnavailableView` ("Waiting for packets…"), `ScrollViewReader`. ✓
- **Iconography & labels**: the "Live" button is icon + text label. The filter button is icon-only — but it mirrors the app's existing icon-only filter button, so no new pattern is introduced (desktop tooltip guidance applies app-wide, not a regression here).
- **Touch targets ≥44pt**: bordered-prominent buttons with padding; toggle/rows are standard Form controls. ✓
- **Dynamic Type / 16px body**: macCatalyst stream rows use `.font(.body)`; phone uses `.caption` matching the existing phone log Table. ✓ (inherits app behavior)
- **Color usage (Section 9)** — minor note: the "LIVE" badge and Packet Stream label use `LogCategories.mesh.color` (system green), reused from the existing Mesh filter row. On a light capsule this green-on-light could be below WCAG AA for small text. It matches existing app usage of that category color, so it's consistent; a future tweak could switch the badge text to Success Green 600 (`#3FB86D`) per Section 9. Not blocking.

Conclusion: conforms at the level of the surrounding app; no blocking changes. Defaults (both accordion sections collapsed) kept.
