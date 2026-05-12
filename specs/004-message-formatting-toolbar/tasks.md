# Tasks: Link Formatting (FR-025 – FR-030)

**Input**: Design documents from `/specs/004-message-formatting-toolbar/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Included — spec.md SC-007 explicitly requires unit test coverage for link formatting.

**Organization**: All tasks belong to User Story 5 (Link Formatting, P2). The existing formatting toolbar (US1–US4, US6) is already implemented. This task list covers only the NEW link formatting work.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US5)
- Exact file paths included in descriptions

---

## Phase 1: Foundational — Helper Functions

**Purpose**: Add link formatting logic to `MarkdownFormatting.swift` — all UI and test tasks depend on these functions existing.

**⚠️ CRITICAL**: UI and test tasks depend on this phase being complete.

- [X] T001 [US5] Add `.link` case to `MarkdownStyle` enum with `openingDelimiter` → `"["`, `closingDelimiter` → `"]"`, `sfSymbol` → `"link"` in `Meshtastic/Helpers/MarkdownFormatting.swift`
- [X] T002 [US5] Implement `isMarkdownLink(_:) -> Bool` function using regex `\[([^\]]+)\]\(([^)]+)\)` to detect `[text](url)` pattern in `Meshtastic/Helpers/MarkdownFormatting.swift`
- [X] T003 [US5] Implement `wrapSelectionWithLink(in:range:url:) -> FormattingResult` — wraps selected text as `[text](url)`, or inserts `[link text](url)` placeholder when range is collapsed, in `Meshtastic/Helpers/MarkdownFormatting.swift`
- [X] T004 [US5] Implement `unwrapLink(in:range:) -> FormattingResult?` — detects `[text](url)` in selection and returns display text only, or nil if not a link, in `Meshtastic/Helpers/MarkdownFormatting.swift`
- [X] T005 [US5] Update `containsMarkdownSyntax(_:) -> Bool` to also return `true` for text containing `[text](url)` link patterns in `Meshtastic/Helpers/MarkdownFormatting.swift`

**Checkpoint**: All link formatting helper functions are available for UI and tests.

---

## Phase 2: Tests — Link Formatting

**Purpose**: Unit tests for all link helper functions per SC-007.

> **NOTE: These tests should FAIL before Phase 1 implementation is correct.**

- [X] T006 [P] [US5] Add `LinkFormattingTests` suite with test for `isMarkdownLink` — true for `[text](url)`, false for plain text, false for partial patterns like `[text]` or `(url)`, in `MeshtasticTests/MarkdownFormattingTests.swift`
- [X] T007 [P] [US5] Add test for `wrapSelectionWithLink` — wraps selected text `hello` with URL `https://example.com` producing `[hello](https://example.com)`, verifies result text and selectedRange covers full link span, in `MeshtasticTests/MarkdownFormattingTests.swift`
- [X] T008 [P] [US5] Add test for `wrapSelectionWithLink` with collapsed cursor — inserts `[link text](https://example.com)` placeholder at cursor position, in `MeshtasticTests/MarkdownFormattingTests.swift`
- [X] T009 [P] [US5] Add test for `unwrapLink` — given `[hello](https://example.com)` selected, returns `hello` as display text; given plain text selected, returns nil, in `MeshtasticTests/MarkdownFormattingTests.swift`
- [X] T010 [P] [US5] Add test for updated `containsMarkdownSyntax` returning true for text containing `[hello](https://example.com)` link syntax, in `MeshtasticTests/MarkdownFormattingTests.swift`

**Checkpoint**: Test suite covers link wrap, unwrap, detect, placeholder insertion, and containsMarkdownSyntax.

---

## Phase 3: UI — Link Button & Dialog

**Purpose**: Add the link button to the toolbar and the URL entry dialog in the view layer.

- [X] T011 [US5] Add `@State` properties `showLinkAlert: Bool = false`, `linkURL: String = ""`, and `pendingLinkRange: Range<String.Index>? = nil` to `FormattingToolbarButtons` in `Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift`
- [X] T012 [US5] Handle `.link` case in `applyFormatting` — check if selected text `isMarkdownLink`, if yes call `unwrapLink` and apply result directly (FR-029), otherwise store selection range in `pendingLinkRange` and set `showLinkAlert = true`, in `Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift`
- [X] T013 [US5] Add `.alert("Insert Link", isPresented: $showLinkAlert)` modifier with `TextField` bound to `$linkURL`, Confirm button disabled when `linkURL.isEmpty` (FR-026) that calls `wrapSelectionWithLink` with `pendingLinkRange` and resets `linkURL` to empty, Cancel button that dismisses without changes, in `Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift`
- [X] T014 [US5] Verify link button renders with `link` SF Symbol, appears after Code button and before AlertButton per FR-030, uses `.buttonStyle(.plain)` and `.frame(minWidth: 44, minHeight: 36)` touch target per FR-006, in `Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift`

**Checkpoint**: Link button is fully functional — dialog appears on tap, confirm wraps text, cancel is no-op, existing links unwrap on tap without dialog.

---

## Phase 4: Polish & Validation

**Purpose**: Final verification across all changes.

- [X] T015 [US5] Run all tests and confirm link formatting tests pass green
- [X] T016 [US5] Run SwiftLint and confirm no new warnings or errors introduced
- [X] T017 Run quickstart.md build & test commands to validate end-to-end compilation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Foundational)**: No dependencies — start immediately
- **Phase 2 (Tests)**: Depends on Phase 1 (functions must exist to compile)
- **Phase 3 (UI)**: Depends on Phase 1 (UI calls helper functions)
- **Phase 4 (Polish)**: Depends on Phases 1–3

### Within Phase 1

- T001 first (enum case needed by all functions)
- T002 before T004 (`isMarkdownLink` used by `unwrapLink`)
- T003 and T004 can run in parallel after T002
- T005 can run in parallel with T003/T004

### Parallel Opportunities

- **Phase 2 + Phase 3** can run in parallel after Phase 1 (different files)
- **T006–T010** (test tasks) are all [P] — independent test cases in same file
- **T011–T014** are sequential within the same file

### Parallel Example

```bash
# After Phase 1 completes, launch in parallel:

# Thread A (tests — MeshtasticTests/MarkdownFormattingTests.swift):
Task T006: "isMarkdownLink detection tests"
Task T007: "wrapSelectionWithLink with selection tests"
Task T008: "wrapSelectionWithLink collapsed cursor tests"
Task T009: "unwrapLink tests"
Task T010: "containsMarkdownSyntax link detection test"

# Thread B (UI — FormattingToolbarButtons.swift):
Task T011: "Add @State properties for link dialog"
Task T012: "Handle .link in applyFormatting"
Task T013: "Add .alert modifier for URL entry"
Task T014: "Verify button positioning and styling"
```

---

## Implementation Strategy

### Single Story Delivery

This task list covers one user story (US5 — Link Formatting, P2). Order:

1. Complete Phase 1: Helper functions in `MarkdownFormatting.swift` (T001–T005)
2. Complete Phase 2 + Phase 3 in parallel (T006–T010 tests + T011–T014 UI)
3. Complete Phase 4: Validation (T015–T017)

All existing formatting (bold, italic, strikethrough, code) remains unchanged.

---

## Notes

- 3 existing files modified, 0 new files created
- `.link` must be last case in `MarkdownStyle` so `ForEach` toolbar ordering places it after Code (FR-030)
- Link button triggers a dialog unlike other buttons — requires `pendingLinkRange` to capture selection before async `.alert`
- No SwiftData schema changes — raw markdown `[text](url)` stored in existing `messagePayload`
- No doc updates required unless user-facing help text changes
