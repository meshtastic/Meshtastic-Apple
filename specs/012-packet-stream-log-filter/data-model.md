# Phase 1 Data Model: Packet Stream Log Filter

This feature introduces no persistent (SwiftData) entities. The "data" here is transient view-model state over the unified OSLog store. Types below describe in-memory structures.

## Entities

### PacketStreamModel (NEW, `@MainActor` `ObservableObject`)

Owns the live tail. Lives at `Views/Settings/Logs/PacketStreamModel.swift`.

| Property | Type | Notes |
|----------|------|-------|
| `visibleEntries` | `[OSLogEntryLog]` | `@Published`. Capped ring, max 1,000 (FR-011). Chronological, newest last. |
| `isStreaming` | `Bool` | `@Published`. Whether the live tail is running (screen active + mode on, FR-003/FR-014). |
| `isPinnedToLiveEdge` | `Bool` | `@Published`. Auto-scroll follows new entries only when true (FR-023/R4). |
| `droppedDueToOverload` | `Bool` | `@Published`. Drives optional "dropping entries" indicator (R3). |
| `pending` | `[OSLogEntryLog]` (private) | Buffer between poll and paced reveal; capped ~1,000 (R2/R3). |
| `lastSeenDate` | `Date?` (private) | Read-position cursor for incremental fetch (R1). |
| `lastSeenKey` | `String?` (private) | date+message hash for boundary de-dup (R1). |

| Method | Behavior |
|--------|----------|
| `start()` | Begin poll loop + reveal ticker. Idempotent. Called on appear when Packet Stream on. |
| `stop()` | Cancel loops; clears `isStreaming`. Called on disappear/background or mode off (FR-014). |
| `poll()` (private) | Fetch Mesh-category entries since `lastSeenDate`, de-dup, enqueue to `pending`, advance cursor; drop oldest pending past cap. |
| `revealTick()` (private) | Move ≤ (6/sec budget) entries `pending → visibleEntries`; drop oldest visible past 1,000. |
| `setPinned(_:)` | Update `isPinnedToLiveEdge` from scroll position. |
| `reset()` | Clear buffers + cursor (on mode toggle or user clear). |

**Validation / rules**:
- Mesh-only, all levels: poll predicate filters `category == "🕸️ Mesh"` and ignores the user's Category/Level selections while streaming (FR-002 override).
- Reveal rate ceiling ≈6 entries/sec (FR-021); no throttle on `poll()` ingestion (FR-022).
- `visibleEntries.count <= 1000` invariant always (FR-011).

**State transitions**:
```
idle ──start()──▶ streaming ──(background / disappear / mode off)──▶ idle
streaming ──poll()──▶ enqueue pending ──revealTick()──▶ append visible (drop oldest >1000)
streaming + scroll-away ──▶ unpinned (auto-scroll paused) ──scroll-to-bottom──▶ pinned
```

### LogFilterState (existing bindings, extended)

Currently `AppLog` holds `categories: Set<Int>` and `levels: Set<Int>` ([AppLog.swift:20](../../Meshtastic/Views/Settings/AppLog.swift#L20)) passed to `AppLogFilter`. Add:

| Property | Type | Notes |
|----------|------|-------|
| `isPacketStreamOn` | `Bool` | `@Published`/`@State`. Top filter control (FR-001/FR-010); when on, overrides categories/levels (FR-002). |
| `categoriesExpanded` | `Bool` | Accordion state for Categories section (FR-005). Default collapsed. |
| `levelsExpanded` | `Bool` | Accordion state for Log Levels section (FR-006). Default collapsed/compact. |

Accordion/expansion state and selections are independent: collapsing never mutates `categories`/`levels` (FR-007/FR-008/FR-009).

### LogCategories (existing enum — unchanged)

`enum LogCategories: Int` in [AppLogFilter.swift:12](../../Meshtastic/Views/Settings/Logs/AppLogFilter.swift#L12). No cases added (decision R5: reuse Mesh, no new `.packet`). Semantics tightened by the audit:

| Case | `description` | Post-audit meaning |
|------|---------------|--------------------|
| `mesh` | `🕸️ Mesh` | **Over-the-air packet events only** (in + out). Packet Stream source. |
| `radio` | `📟 Radio` | Device serial/firmware debug only. |
| `admin` | `🏛 Admin` | Config/admin/setup activity. |
| `data` | `🗄️ Data` | Persistence/save events. |
| `transport` | `🚚 Transport` | Connection/handshake/link only (no packet sends after audit). |
| others | — | Unchanged. |

### OSLogEntryLog (system type — read-only)

The unit displayed: `date`, `composedMessage`, `category`, `level`, `subsystem`. Already `Identifiable` via existing retroactive conformance ([AppLog.swift:273](../../Meshtastic/Views/Settings/AppLog.swift#L273)). PII redaction is applied at write time via `privacy:` markers (FR-024); the entry's `composedMessage` reflects redaction only for external readers, not the owning process.
