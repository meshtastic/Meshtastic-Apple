# Tasks: Packet Stream Log Filter

**Input**: Design documents from `/specs/012-packet-stream-log-filter/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/log-viewer-ui-contract.md](contracts/log-viewer-ui-contract.md), [quickstart.md](quickstart.md)

**Tests**: Included — automated tests are requested in plan.md and quickstart.md (`PacketStreamModelTests`, filter snapshot tests). Use the Swift Testing framework (`@Suite`/`@Test`/`#expect`), not XCTest.

**Organization**: Tasks are grouped by user story (from spec.md) so each story is an independently testable increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US4 map to the spec's user stories
- Paths are repo-relative; this is a single Xcode project under `Meshtastic/` with tests in `MeshtasticTests/`

---

## Phase 1: Setup

- [X] T001 Fetch and review the [Meshtastic Client Design Standards](https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md) for list/filter/toggle conventions (Constitution VIII); capture the conventions to apply to the filter accordions and Packet Stream control as a short note in `specs/012-packet-stream-log-filter/research.md` (append under a "Design standards" heading).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared state/signature changes touched by US1, US3, and US4. No user-visible behavior yet.

**⚠️ CRITICAL**: Complete before starting US1/US3/US4 UI work (US2 audit is independent and may start anytime).

- [X] T002 Add new filter state to `Meshtastic/Views/Settings/AppLog.swift`: `@State private var isPacketStreamOn = false`, `@State private var categoriesExpanded = false`, `@State private var levelsExpanded = false`; pass them as bindings into `AppLogFilter`.
- [X] T003 Extend the `AppLogFilter` initializer/signature in `Meshtastic/Views/Settings/Logs/AppLogFilter.swift` to accept `@Binding var isPacketStreamOn: Bool`, `@Binding var categoriesExpanded: Bool`, `@Binding var levelsExpanded: Bool` (no layout change yet); update the `#Preview` to pass `.constant(...)` values so the file compiles.

**Checkpoint**: Filter sheet compiles with the new bindings; stories can build on them.

---

## Phase 3: User Story 1 - Watch live mesh packet traffic (Priority: P1) 🎯 MVP

**Goal**: A working live tail of Mesh-category packets — paced, bounded, auto-scrolling with read-pause — toggled from the filter.

**Independent Test**: With a connected device and traffic, enable Packet Stream → only Mesh entries appear, update automatically (~5s), flow at a readable pace on a busy mesh, pause on scroll-back, and the view returns to normal when disabled.

### Tests for User Story 1

- [X] T004 [P] [US1] Create `MeshtasticTests/PacketStreamModelTests.swift` (Swift Testing) covering: reveal pacing never exceeds the per-second budget on a burst; `visibleEntries.count` never exceeds 1,000 with oldest evicted first; incremental "since date" filtering returns only newer entries with boundary de-dup; Mesh-only predicate excludes other categories. (Write first; expect failing until T006–T008.)

### Implementation for User Story 1

- [X] T005 [US1] Add an incremental fetch to `Meshtastic/Extensions/Logger.swift`: `static func fetch(predicateFormat:since:) async throws -> [OSLogEntryLog]` that uses `store.position(date: since)` when `since != nil`, else preserves the current boot-position behavior (keep existing `fetch(predicateFormat:)` working).
- [X] T006 [US1] Create `Meshtastic/Views/Settings/Logs/PacketStreamModel.swift` — `@MainActor final class PacketStreamModel: ObservableObject` per [data-model.md](data-model.md): `@Published visibleEntries/isStreaming/isPinnedToLiveEdge/droppedDueToOverload`, private `pending`/`lastSeenDate`/`lastSeenKey`; `start()/stop()/reset()/setPinned(_:)`; `poll()` (Mesh-category predicate, since-date, de-dup, enqueue, cap pending) and `revealTick()` (move ≤≈6/sec pending→visible, cap 1,000 drop-oldest).
- [X] T007 [US1] Implement the poll loop and reveal ticker in `PacketStreamModel` using `Task` + `Task.sleep` (poll ~1s; ticker ~167ms or batched to ≈6/sec); ensure `stop()` cancels both and `start()` is idempotent.
- [X] T008 [US1] Add a streaming render path to `Meshtastic/Views/Settings/AppLog.swift` covering **both** layout branches (phone `idiom == .phone` and iPad/macCatalyst): when `isPacketStreamOn`, show a bottom-anchored chronological list of `model.visibleEntries` (reuse `ScrollViewReader` + bottom anchor) instead of the static `Table`. **Reuse the existing log row presentation** (the `composedMessage`/level-color row already used in the Table columns) rather than a new row design; keep `LogDetail` tap. Show a "waiting for packets" `ContentUnavailableView` when empty (FR-012). Extract a shared streaming subview so both idiom branches use one implementation (Const VII parity).
- [X] T009 [US1] Wire auto-scroll + read-pause in `AppLog.swift`: scroll to bottom on new entries only while `model.isPinnedToLiveEdge`; update pinned state from scroll position so scrolling away pauses and returning resumes (FR-020/FR-023).
- [X] T010 [US1] Wire lifecycle in `AppLog.swift`: start the model when Packet Stream turns on and the screen is active; `stop()` on disappear, background, and scenePhase != active; resume on return (FR-003/FR-014). Apply active search text to `visibleEntries` (FR-013). Route the export/copy toolbar action through the existing Mesh-category fetch (`searchAppLogs` with the Mesh category selected) when streaming, so the export is the full Mesh-category packet log rather than the capped on-screen buffer (FR-024 / Edge: Sharing/exporting).
- [X] T011 [US1] Add a functional Packet Stream toggle to `AppLogFilter` bound to `isPacketStreamOn` (placement/prominence refined in US4); confirm enabling overrides to Mesh-only/all-levels in the viewer and disabling restores normal mode (FR-002/FR-004).

**Checkpoint**: Live, paced, bounded Mesh packet stream works end-to-end and is independently demoable (MVP).

---

## Phase 4: User Story 2 - Trust that the stream shows only real packets (Priority: P1)

**Goal**: Audit so the Mesh category contains only over-the-air packet events (in + out); relocate non-packet lines; preserve PII redaction.

**Independent Test**: With device serial logging ON, the Mesh category / Packet Stream shows 0 serial/config/admin-only/persistence lines; sent packets appear; relocated lines show under Radio/Admin/Data.

**Note**: Independent of US1 code (different files). May proceed in parallel with US1; both are P1.

- [X] T012 [US2] Enumerate every `Logger.mesh.*` call site (e.g., `grep -rn "Logger.mesh" Meshtastic/`) and classify each as packet vs non-packet; record the audit list as `specs/012-packet-stream-log-filter/contracts/mesh-audit.md`.
- [X] T013 [P] [US2] Relocate non-packet config/admin/setup lines off `Logger.mesh` → `Logger.admin` in `Meshtastic/Helpers/MeshPackets.swift` (e.g., config-received, myInfo, canned/admin responses), preserving each line's existing `privacy:` markers verbatim.
- [X] T014 [P] [US2] Move persistence/save lines that leak onto `Logger.mesh` → `Logger.data` in `Meshtastic/Persistence/UpdateSwiftData.swift` (verify the device-config-received line at ~`:285` is reclassified); preserve `privacy:` markers.
- [X] T015 [US2] Move outbound over-the-air packet sends from `Logger.transport` → `Logger.mesh` in `Meshtastic/Accessory/Accessory Manager/AccessoryManager.swift` `send(_:)` (~`:421`) and `Meshtastic/Accessory/Accessory Manager/AccessoryManager+ToRadio.swift`; keep connect/handshake/link lines on `.transport`; preserve `privacy:` markers (FR-019).
- [X] T016 [US2] Verify inbound dispatch in `AccessoryManager.swift` `processFromRadio` (~`:589`) logs each handled packet under `.mesh` and that serial `didReceiveLog` (~`:514`) stays on `.radio` (no change beyond confirmation); add a one-line `.mesh` packet log at the dispatch point only if a packet type is currently silent.
- [X] T017 [US2] PII safety pass: diff the audit changes and confirm no `privacy: .private`/`.private(mask: .none)` was downgraded to `.public` (FR-024); spot-check coordinate-bearing position lines.

**Checkpoint**: Mesh category is a clean, both-directions packet signal; Packet Stream (US1) now trustworthy.

---

## Phase 5: User Story 3 - Collapse/expand filter sections (Priority: P2)

**Goal**: Categories and Log Levels become independent accordions; collapsing preserves selections and shrinks the panel.

**Independent Test**: Open filter, collapse both sections → panel ≥50% shorter; expand → toggles return with selections intact.

- [X] T018 [US3] Convert the Categories and Log Levels `Section`s in `Meshtastic/Views/Settings/Logs/AppLogFilter.swift` to independent `DisclosureGroup`s bound to `categoriesExpanded`/`levelsExpanded`; keep the existing "All" header action and `selectionRow` rows; default both collapsed (or per design-standards note from T001).
- [X] T019 [US3] Confirm collapse/expand never mutates `categories`/`levels` and collapsed selections still apply when Packet Stream is OFF (FR-007/FR-008/FR-009); adjust bindings if needed.
- [X] T020 [P] [US3] Add snapshot test(s) to `MeshtasticTests/SwiftUIViewSnapshotTests.swift` for `AppLogFilter` with sections collapsed and expanded (record references on a clean run; pass explicit `height:` since the sheet scrolls). The accordion layout-change is asserted (collapsed vs expanded render differs); the ≥50% footprint reduction (SC-003) is verified on-device in the quickstart pass since a scrollable Form has no reliable intrinsic height.

**Checkpoint**: Compact, collapsible filter usable independently of the stream.

---

## Phase 6: User Story 4 - Packet Stream as the first filter option (Priority: P3)

**Goal**: Make the Packet Stream control the topmost, clearly-indicated option and visibly disable the accordions while active.

**Independent Test**: Open filter → Packet Stream is the first control above both groups; enabling it shows active state and dims/disables Categories & Log Levels.

- [X] T021 [US4] In `Meshtastic/Views/Settings/Logs/AppLogFilter.swift`, position the Packet Stream control as the first element (top, above both `DisclosureGroup`s) with a clear active indication (FR-001/FR-010), following the T001 design-standards note.
- [X] T022 [US4] When `isPacketStreamOn`, disable/dim the Categories and Log Levels groups to reflect the override (FR-002); re-enable when off.
- [X] T023 [US4] Add/extend a snapshot test in `MeshtasticTests/SwiftUIViewSnapshotTests.swift` for the Packet-Stream-on filter state (top control prominent, groups disabled). (Not `[P]`: edits the same file as T020 — serialize the two.)

**Checkpoint**: Discoverable, override-aware filter layout complete.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T024 [P] Verify export/copy while streaming: open an exported CSV / Console with a position packet visible and confirm coordinates render redacted (`<private>`), not raw (FR-024/SC-010).
- [ ] T025 [P] Performance check on a busy mesh (or `PerformanceSeedData`): confirm smooth scroll, bounded memory at the 1,000-entry cap, and ≤≈6/sec reveal (SC-005/SC-008).
- [X] T026 [P] Design-standards conformance pass over the final filter + stream UI against the T001 notes (Constitution VIII).
- [X] T027 [P] Update `Meshtastic/RELEASENOTES.md` (and any log-viewer docs) to mention Packet Stream and the accordion filter.
- [X] T028 Run the full test suite (Swift Testing + snapshots) and SwiftLint; ensure lint-clean per Constitution VI before PR.
- [ ] T029 Walk the [quickstart.md](quickstart.md) manual checklist end-to-end on device and confirm each FR/SC check passes.

---

## Dependencies & Execution Order

- **Setup (T001)** → informs all UI tasks.
- **Foundational (T002–T003)** → blocks US1/US3/US4 UI; must finish first.
- **US1 (T004–T011)** → MVP. Depends on Foundational. T005 before T006/T007; T006/T007 before T008–T011.
- **US2 (T012–T017)** → independent of US1 (different files); can run in parallel. T012 first; T013/T014 are [P]; T015 then T016/T017.
- **US3 (T018–T020)** → depends on Foundational (T003). Independent of US1/US2.
- **US4 (T021–T023)** → depends on US1 (toggle exists, T011) and US3 (accordion layout, T018).
- **Polish (T024–T029)** → after the stories they validate; T028/T029 last.

### Story completion order (by priority)
US1 (P1, MVP) → US2 (P1) → US3 (P2) → US4 (P3). US1 and US2 may proceed concurrently.

### Parallel opportunities
- Within US2: `T013` (MeshPackets) ∥ `T014` (UpdateSwiftData) — different files.
- Across stories after Foundational: a UI dev on US3 (`AppLogFilter`) while another does US2 audit (Accessory/MeshPackets) and a third builds US1's `PacketStreamModel`.
- Verification/polish tasks `T024`, `T025`, `T026`, `T027` are [P] (different files/activities). `T020` and `T023` both edit `SwiftUIViewSnapshotTests.swift`, so they serialize (only T020 is [P]).

## Implementation Strategy

- **MVP = US1 only**: a live, paced, bounded packet stream toggled from the filter. Demoable on its own (it streams the Mesh category as-is).
- **Next increment = US2**: the audit makes that stream trustworthy on devices with serial logging — the highest-value follow-on, also P1.
- **Then US3 / US4**: filter ergonomics and discoverability.
- Keep the audit (US2) behavior-preserving except category labels; verify PII redaction (T017/T024) before any commit that touches logging.
