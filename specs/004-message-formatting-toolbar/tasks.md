# Tasks: Message Formatting Toolbar (Pure SwiftUI)

**Input**: Design documents from `/specs/004-message-formatting-toolbar/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Included — spec.md SC-007 requires unit test coverage for all formatting helpers; plan.md lists snapshot tests.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create new files and establish the formatting helper infrastructure

- [x] T001 Create `MarkdownStyle` enum (cases: bold, italic, strikethrough, code) with `openingDelimiter`, `closingDelimiter`, and `sfSymbol` computed properties, and `FormattingResult` struct (text: String, selectedRange: Range<String.Index>) in Meshtastic/Helpers/MarkdownFormatting.swift
- [x] T002 [P] Create empty `FormattingToolbarButtons` SwiftUI view stub with required bindings (`typingMessage: Binding<String>`, `textSelection: Binding<TextSelection?>`) in Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift
- [x] T003 [P] Create empty `MessagePreview` SwiftUI view stub accepting `text: String` input in Meshtastic/Views/Messages/TextMessageField/MessagePreview.swift

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement the pure formatting logic that all user stories depend on

**⚠️ CRITICAL**: No user story UI work can begin until these helper functions are complete and tested

- [x] T004 Implement `wrapSelection(in:range:style:) -> FormattingResult` in Meshtastic/Helpers/MarkdownFormatting.swift — wraps selected substring with delimiters, or removes them if already wrapped (toggle behaviour per FR-008, FR-009)
- [x] T005 Implement `insertDelimiters(in:at:style:) -> FormattingResult` in Meshtastic/Helpers/MarkdownFormatting.swift — inserts opening+closing delimiters at cursor position, returns cursor positioned between them (FR-010)
- [x] T006 Implement `isStyleActive(in:range:style:) -> Bool` in Meshtastic/Helpers/MarkdownFormatting.swift — scans outward from cursor to detect enclosing delimiter pairs, handles bold (`**`) vs italic (`*`) disambiguation by checking longer delimiter first
- [x] T007 Implement `containsMarkdownSyntax(_:) -> Bool` in Meshtastic/Helpers/MarkdownFormatting.swift — returns true if text contains any of `*`, `~`, or `` ` `` characters (FR-012)
- [x] T008 Create unit tests for `wrapSelection` (wrap bold/italic/strikethrough/code, toggle off each style) using Swift Testing (`@Suite`, `@Test`, `#expect`) in MeshtasticTests/MarkdownFormattingTests.swift
- [x] T009 Create unit tests for `insertDelimiters` (insert at cursor for each style, empty string, end of string) in MeshtasticTests/MarkdownFormattingTests.swift
- [x] T010 Create unit tests for `isStyleActive` (cursor inside bold, italic, strikethrough, code, outside delimiters, bold vs italic disambiguation) in MeshtasticTests/MarkdownFormattingTests.swift
- [x] T011 Create unit tests for `containsMarkdownSyntax` (plain text returns false, each delimiter type returns true, empty string returns false) in MeshtasticTests/MarkdownFormattingTests.swift

**Checkpoint**: All formatting helper functions implemented and passing tests — UI phases can begin

---

## Phase 3: User Story 1 — Apply Formatting to Selected Text (Priority: P1) 🎯 MVP

**Goal**: Users on iOS 18+ can select text in the compose field and tap a formatting button to wrap/unwrap it with markdown delimiters

**Independent Test**: Type text, select a word, tap Bold → verify `**word**` in compose field, bold in preview, bold in sent message bubble

### Implementation for User Story 1

- [x] T012 [US1] Add `@State private var textSelection: TextSelection?` property to `TextMessageField` in Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift
- [x] T013 [US1] Add `if #available(iOS 18.0, macOS 15.0, *)` branch in `TextMessageField.body` that replaces `TextField` with `TextEditor(text: $typingMessage, selection: $textSelection)` and applies matching visual styling (`.scrollContentBackground(.hidden)`, same `RoundedRectangle(cornerRadius: 20)` stroke border, `.padding(.horizontal, 16)`, `.padding(.vertical, 12)`, `.foregroundColor(.primary)`) in Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift
- [x] T014 [US1] Preserve existing `TextField` in the `else` branch of the `#available` check for iOS 17.x fallback — no changes to appearance or behaviour in Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift
- [x] T015 [US1] Implement `FormattingToolbarButtons` view with four buttons (Bold, Italic, Strikethrough, Code) using SF Symbols (`bold`, `italic`, `strikethrough`, `chevron.left.forwardslash.chevron.right`), 44×44pt minimum touch targets via `.frame(minWidth: 44, minHeight: 44)`, and accessibility labels ("Bold", "Italic", "Strikethrough", "Code") in Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift
- [x] T016 [US1] Wire each formatting button tap to extract `Range<String.Index>` from `textSelection`, call `wrapSelection(in:range:style:)` when selection is non-empty, and update both `typingMessage` and `textSelection` bindings with the result in Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift — guard against nil `textSelection` by disabling buttons when it is nil
- [x] T017 [US1] Add `FormattingToolbarButtons` to the keyboard toolbar `HStack` before existing buttons (AlertButton, RequestPositionButton, TextMessageSize), only inside the iOS 18+ `#available` branch, in Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift — **verify** the Mac Catalyst character palette button (`face.smiling`) remains present in the iOS 18+ toolbar branch alongside the new formatting buttons (FR-017)
- [x] T018 [US1] Add `.onKeyPress(.return)` modifier on `TextEditor` gated with `#if targetEnvironment(macCatalyst)` to call `sendMessage()` and return `.handled` for Mac Catalyst enter-to-send behaviour in Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift

**Checkpoint**: US1 complete — formatting buttons appear on iOS 18+, wrapping/unwrapping selected text works, iOS 17.x unchanged

---

## Phase 4: User Story 2 — Insert Formatting Delimiters at Cursor (Priority: P2)

**Goal**: Users can tap a formatting button with no text selected to insert delimiters at the cursor, with the cursor placed between them for immediate typing

**Independent Test**: Place cursor in compose field, tap Italic → verify `**` inserted with cursor between the two `*` characters, type text, confirm preview shows italic

### Implementation for User Story 2

- [x] T019 [US2] Add collapsed-cursor detection in `FormattingToolbarButtons` button tap handler — when `textSelection` range is empty (`lowerBound == upperBound`), call `insertDelimiters(in:at:style:)` instead of `wrapSelection` in Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift
- [x] T020 [US2] Ensure cursor repositioning after `insertDelimiters` correctly sets `textSelection` to the empty range between delimiters via `TextSelection(range: result.selectedRange)` in Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift

**Checkpoint**: US2 complete — format-then-type workflow functional for all four styles

---

## Phase 5: User Story 3 — Live Preview of Formatted Message (Priority: P2)

**Goal**: A read-only preview bubble below the compose field shows rendered markdown in real time as the user types

**Independent Test**: Type `**hello** world` in compose field → verify preview shows "hello" bold and "world" plain, preview hidden when compose field has no markdown

### Implementation for User Story 3

- [x] T021 [US3] Implement `MessagePreview` view body with `Text(LocalizedStringKey(text))` styled as a sent message bubble (accent background colour, rounded corners, white foreground, `.padding()`) in Meshtastic/Views/Messages/TextMessageField/MessagePreview.swift
- [x] T022 [US3] Add visibility logic to `MessagePreview` — wrap content in conditional check using `containsMarkdownSyntax(text)`, return `EmptyView` when false (FR-012) in Meshtastic/Views/Messages/TextMessageField/MessagePreview.swift
- [x] T023 [US3] Integrate `MessagePreview(text: typingMessage)` below the `TextEditor` inside the iOS 18+ `#available` branch of `TextMessageField.body` in Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift

**Checkpoint**: US3 complete — live preview appears/disappears based on markdown content, renders bold/italic/strikethrough/code

---

## Phase 6: User Story 4 — Active Formatting State Indication (Priority: P3)

**Goal**: Toolbar buttons visually indicate when the cursor is inside existing markdown delimiters (accent-filled pill background with white foreground)

**Independent Test**: Place cursor inside `**bold text**` → verify Bold button shows active state; move cursor outside → button returns to default

### Implementation for User Story 4

- [x] T024 [US4] Add computed active-state detection in `FormattingToolbarButtons` — for each `MarkdownStyle`, call `isStyleActive(in: typingMessage, range: currentRange, style:)` using the range extracted from `textSelection` in Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift
- [x] T025 [US4] Apply active button styling — `Capsule().fill(Color.accentColor)` background with `.foregroundStyle(.white)` when active, `.foregroundStyle(.secondary)` when inactive (FR-007, iMessage-style toggle) in Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift

**Checkpoint**: US4 complete — buttons reflect formatting state at cursor position

---

## Phase 7: User Story 5 — Combined Bold+Italic Formatting (Priority: P3)

**Goal**: Users can apply both bold and italic to the same text, producing `***text***` triple-star syntax

**Independent Test**: Select text, tap Bold → `**text**`, select bold text, tap Italic → `***text***` with both styles in preview

### Implementation for User Story 5

- [x] T026 [US5] Verify or extend `wrapSelection` to handle bold+italic overlap — wrapping `**text**` (with the `**` delimiters included in the selection) with italic should produce `***text***` and wrapping `*text*` (with `*` delimiters included) with bold should produce `***text***` (FR-016) in Meshtastic/Helpers/MarkdownFormatting.swift
- [x] T027 [US5] Add unit tests for bold+italic combination (apply bold then italic → `***text***`, apply italic then bold → `***text***`, toggle bold off from `***text***` leaving `*text*`) in MeshtasticTests/MarkdownFormattingTests.swift
- [x] T028 [US5] Verify `isStyleActive` correctly detects both bold and italic as active when cursor is inside `***text***` in Meshtastic/Helpers/MarkdownFormatting.swift

**Checkpoint**: US5 complete — combined formatting works correctly with toggle and detection

---

## Phase 8: User Story 6 — iOS 17 Compatibility (Priority: P1)

**Goal**: Users on iOS 17.x / macOS 14.x see absolutely no change to their messaging experience

**Independent Test**: Run on iOS 17.x simulator → verify no TextEditor, no formatting buttons, no preview — identical to pre-feature state

### Implementation for User Story 6

- [x] T029 [US6] Verify the `else` fallback branch in `TextMessageField` preserves the existing `TextField` with identical modifiers, keyboard toolbar (character palette on Mac Catalyst, AlertButton, RequestPositionButton, TextMessageSize), `onSubmit` behaviour, and `onChange` byte-limit enforcement in Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift
- [x] T030 [US6] Verify no iOS 18-only APIs (`TextSelection`, `FormattingToolbarButtons`, `MessagePreview`) leak outside the `if #available(iOS 18.0, macOS 15.0, *)` guard in Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift

**Checkpoint**: US6 complete — iOS 17.x experience is identical to pre-feature state

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Snapshot tests, documentation, Mac Catalyst verification, and final validation

- [x] T031 [P] Add snapshot tests for `FormattingToolbarButtons` (default state, bold active, multiple active) using the project's `renderImage` + `assertViewSnapshot` helper in MeshtasticTests/SwiftUIViewSnapshotTests.swift
- [x] T032 [P] Add snapshot tests for `MessagePreview` (bold text, mixed formatting, hidden when no markdown) using the project's `renderImage` + `assertViewSnapshot` helper in MeshtasticTests/SwiftUIViewSnapshotTests.swift
- [x] T033 [P] Verify Mac Catalyst toolbar layout — `#if targetEnvironment(macCatalyst)` block includes both character palette button and four formatting buttons, all accessible, in Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift
- [x] T034 Update user documentation for message formatting in docs/user/messages.md — document the formatting toolbar, supported styles (bold, italic, strikethrough, code), live preview, and iOS 18+ availability
- [x] T035 Regenerate bundled HTML docs: `bash scripts/build-docs.sh --output Meshtastic/Resources/docs --beta`
- [x] T036 Run quickstart.md validation — build on iOS 18+ simulator, test all four formatting styles with selection and cursor-insert, verify live preview, verify iOS 17.x fallback, verify Mac Catalyst enter-to-send

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on T001 (`MarkdownStyle` enum) — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 completion (T004–T011)
- **US2 (Phase 4)**: Depends on US1 (T015–T016 for button infrastructure)
- **US3 (Phase 5)**: Depends on Phase 2 (T007 for `containsMarkdownSyntax`), can run in parallel with US1/US2
- **US4 (Phase 6)**: Depends on US1 (T015 for button views) and Phase 2 (T006 for `isStyleActive`)
- **US5 (Phase 7)**: Depends on Phase 2 (T004 for `wrapSelection`) and US4 (T024 for active detection)
- **US6 (Phase 8)**: Depends on US1 (T013–T014 for the `#available` branching)
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — no dependencies on other stories
- **US2 (P2)**: Depends on US1 (reuses button infrastructure from T015–T016)
- **US3 (P2)**: Can start after Phase 2 — independent of US1/US2 (different file: MessagePreview.swift)
- **US4 (P3)**: Depends on US1 (button views must exist)
- **US5 (P3)**: Depends on Phase 2 (formatting logic)
- **US6 (P1)**: Depends on US1 (fallback branch created during `#available` split)

### Within Each User Story

- Helper functions before views
- Views before integration wiring
- Core implementation before polish

### Parallel Opportunities

- **Phase 1**: T002 and T003 can run in parallel (different files)
- **Phase 2**: T004–T007 are sequential (same file, cumulative); T008–T011 can each start after their respective function
- **Phase 3 + Phase 5**: US1 and US3 can run in parallel (US1 modifies TextMessageField.swift + FormattingToolbarButtons.swift; US3 creates MessagePreview.swift)
- **Phase 6 + Phase 7**: US4 and US5 can run in parallel (US4 modifies FormattingToolbarButtons.swift; US5 modifies MarkdownFormatting.swift)
- **Phase 9**: T031, T032, and T033 can run in parallel (independent concerns)

---

## Parallel Example: Phase 2 (Foundational)

```
T004 (wrapSelection)
  └──► T008 (unit tests for wrapSelection)
T005 (insertDelimiters)
  └──► T009 (unit tests for insertDelimiters)
T006 (isStyleActive)
  └──► T010 (unit tests for isStyleActive)
T007 (containsMarkdownSyntax)
  └──► T011 (unit tests for containsMarkdownSyntax)
```

## Parallel Example: User Stories after Phase 2

```
Phase 2 complete
  ├──► US1 (Phase 3): TextEditor + FormattingToolbarButtons
  │     ├──► US2 (Phase 4): cursor-insert in buttons
  │     ├──► US4 (Phase 6): active state in buttons
  │     └──► US6 (Phase 8): verify fallback
  ├──► US3 (Phase 5): MessagePreview (independent file)
  └──► US5 (Phase 7): bold+italic logic (independent file)
```

---

## Implementation Strategy

### MVP Scope (Recommended First Delivery)

**Phases 1 + 2 + 3 (US1) + 5 (US3) + 8 (US6)** — delivers:
- Core formatting (select text → tap button → markdown wrapped/unwrapped)
- Live preview showing rendered markdown
- iOS 17.x fallback safety

This is a shippable increment that validates the entire pure SwiftUI approach.

### Incremental Additions

- **+US2**: Cursor-insert workflow (small delta on US1 buttons)
- **+US4**: Active state indication (polish on US1 buttons)
- **+US5**: Bold+italic combination (edge case in helper logic)
- **+Polish**: Snapshot tests, documentation, final validation

### File Summary

| File | Action | Phase |
|------|--------|-------|
| `Meshtastic/Helpers/MarkdownFormatting.swift` | CREATE | Phase 1–2 |
| `Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift` | CREATE | Phase 1, 3–4, 6 |
| `Meshtastic/Views/Messages/TextMessageField/MessagePreview.swift` | CREATE | Phase 1, 5 |
| `Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift` | MODIFY | Phase 3, 5, 8 |
| `MeshtasticTests/MarkdownFormattingTests.swift` | CREATE | Phase 2, 7 |
| `MeshtasticTests/SwiftUIViewSnapshotTests.swift` | MODIFY | Phase 9 |
| `docs/user/messages.md` | MODIFY | Phase 9 |

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- All new code must use tabs for indentation, `// MARK: -` sections, `Logger` (no `print()`)
- All views are pure SwiftUI — no UIKit, no `UIViewRepresentable`, no `NSAttributedString` (FR-019)
- `MarkdownStyle` enum and `FormattingResult` struct are shared types used across helper functions and views
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently

---

## Summary

| Metric | Value |
|--------|-------|
| **Total tasks** | 36 |
| **Phase 1 (Setup)** | 3 tasks |
| **Phase 2 (Foundational)** | 8 tasks |
| **US1 — Apply Formatting (P1)** | 7 tasks |
| **US2 — Insert at Cursor (P2)** | 2 tasks |
| **US3 — Live Preview (P2)** | 3 tasks |
| **US4 — Active State (P3)** | 2 tasks |
| **US5 — Bold+Italic (P3)** | 3 tasks |
| **US6 — iOS 17 Compat (P1)** | 2 tasks |
| **Polish** | 6 tasks |
| **Parallel opportunities** | 8 identified |
| **New files** | 3 (`MarkdownFormatting.swift`, `FormattingToolbarButtons.swift`, `MessagePreview.swift`) |
| **Modified files** | 2 (`TextMessageField.swift`, `SwiftUIViewSnapshotTests.swift`) |
| **New test file** | 1 (`MarkdownFormattingTests.swift`) |
