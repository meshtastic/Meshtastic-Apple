# Implementation Plan: Link Formatting (FR-025 – FR-030)

**Branch**: `004-message-formatting-toolbar` | **Date**: 2026-05-11 | **Spec**: `specs/004-message-formatting-toolbar/spec.md`
**Input**: Feature specification from `/specs/004-message-formatting-toolbar/spec.md` — User Story 5 (Link Formatting)

## Summary

Add a Link formatting button to the existing markdown formatting toolbar. When tapped, it presents a URL entry dialog and wraps selected text in `[text](url)` markdown link syntax. Supports wrap, unwrap (toggle-off), and placeholder insertion at collapsed cursor. Three new helper functions in `MarkdownFormatting.swift`, UI changes in `FormattingToolbarButtons.swift`, and new test coverage.

## Technical Context

**Language/Version**: Swift (latest stable)  
**Primary Dependencies**: SwiftUI (TextEditor, TextSelection — iOS 18+)  
**Storage**: N/A (no schema changes — raw markdown stored in existing `messagePayload`)  
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`)  
**Target Platform**: iOS 18+ / macOS 15+ (Mac Catalyst)  
**Project Type**: Mobile app (iOS/iPadOS/macOS)  
**Performance Goals**: N/A (single-tap formatting operation)  
**Constraints**: 200-byte message limit, pure SwiftUI (no UIKit), SF Symbols only  
**Scale/Scope**: 3 files modified, ~150 lines added

## Constitution Check

*GATE: All checks pass.*

| Principle | Status | Notes |
|---|---|---|
| I. SwiftUI-Native | ✅ | All UI is SwiftUI. `.alert` is native SwiftUI. No UIKit. |
| II. SwiftData Persistence | ✅ | No schema changes. Raw markdown stored in existing fields. |
| III. Protocol-Oriented Transport | ✅ | No transport changes. |
| IV. Structured Logging | ✅ | No logging needed for UI formatting helpers. |
| V. Protobuf Contract Fidelity | ✅ | No proto changes. |
| VI. Lint-Clean Commits | ✅ | Will follow SwiftLint rules (tabs, line length). |
| VII. Platform Parity | ✅ | `@available(iOS 18.0, macOS 15.0, *)` guard. iOS 17 unaffected. |
| VIII. Design Standards | ✅ | Link button uses SF Symbol `link`, 44×36pt touch target, `.buttonStyle(.plain)`. |

## Project Structure

### Documentation (this feature)

```text
specs/004-message-formatting-toolbar/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── link-formatting.md
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (files to modify)

```text
Meshtastic/
├── Helpers/
│   └── MarkdownFormatting.swift          # Add .link enum case + 3 new functions
└── Views/Messages/TextMessageField/
    └── FormattingToolbarButtons.swift    # Add link dialog UI + state

MeshtasticTests/
└── MarkdownFormattingTests.swift         # Add LinkFormattingTests suite
```

**Structure Decision**: All changes are within existing files — no new files needed.

## Complexity Tracking

No constitution violations. No complexity justification needed.
