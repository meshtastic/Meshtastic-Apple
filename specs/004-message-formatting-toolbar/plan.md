# Implementation Plan: Message Formatting Toolbar (Pure SwiftUI)

**Branch**: `004-message-formatting-toolbar` | **Date**: 2026-05-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-message-formatting-toolbar/spec.md`

## Summary

Add a markdown formatting toolbar to the message compose UI using a pure SwiftUI approach. On iOS 18+ / macOS 15+, the existing `TextField` is replaced with a `TextEditor(text:selection:)` that exposes cursor position and selection range via `TextSelection?`. Four formatting buttons (Bold, Italic, Strikethrough, Code) are added to the keyboard toolbar. Users type/see raw markdown in the compose field with a live preview rendered below via `Text(LocalizedStringKey(...))`. iOS 17.x / macOS 14.x users see zero changes. No UIKit, no `UIViewRepresentable`, no `NSAttributedString`.

## Technical Context

**Language/Version**: Swift (latest stable), Swift Concurrency (`async/await`, `@MainActor`)
**Primary Dependencies**: SwiftUI (`TextEditor`, `TextSelection`), SF Symbols
**Storage**: SwiftData (existing `MessageEntity` — no schema changes required)
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`); custom snapshot renderer
**Target Platform**: iOS 18+ / macOS 15+ (Mac Catalyst) for new UI; iOS 17.x / macOS 14.x graceful fallback
**Project Type**: Mobile app (iOS/iPadOS/macOS via Catalyst)
**Performance Goals**: Live preview updates at typing speed (< 16ms per keystroke)
**Constraints**: 200-byte message limit on raw `typingMessage` string; no UIKit views permitted
**Scale/Scope**: 4 new/modified files in `Meshtastic/Views/Messages/TextMessageField/`, 1 new helper file, unit + snapshot tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ PASS | Pure SwiftUI — `TextEditor`, `Text`, SF Symbols. No UIKit. |
| II. SwiftData Persistence | ✅ PASS | No schema changes. Existing `MessageEntity` stores raw markdown in `messagePayload` as-is. |
| III. Protocol-Oriented Transport | ✅ N/A | No transport changes. `sendMessage()` receives the raw markdown string. |
| IV. Structured Logging | ✅ PASS | Any logging will use `Logger` categories. No `print()`. |
| V. Protobuf Contract Fidelity | ✅ N/A | No protobuf changes. Message payload is an opaque string. |
| VI. Lint-Clean Commits | ✅ PASS | All code will pass SwiftLint. |
| VII. Platform Parity | ✅ PASS | iOS 18+ gated with `if #available`. iOS 17.x fallback preserves existing `TextField`. Mac Catalyst supported with character palette preserved. |
| VIII. Design Standards | ✅ PASS | Will follow Meshtastic Design Standards for button sizing, colours, and layout. |

**Gate result**: ALL PASS — proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/004-message-formatting-toolbar/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── markdown-formatting-api.md
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
Meshtastic/Views/Messages/TextMessageField/
├── TextMessageField.swift          # MODIFIED — conditional TextEditor vs TextField
├── AlertButton.swift               # UNCHANGED
├── RequestPositionButton.swift     # UNCHANGED
├── TextMessageSize.swift           # UNCHANGED
├── FormattingToolbarButtons.swift  # NEW — formatting button row component
└── MessagePreview.swift            # NEW — live markdown preview bubble

Meshtastic/Helpers/
└── MarkdownFormatting.swift        # NEW — delimiter wrap/unwrap/detect logic

MeshtasticTests/
├── MarkdownFormattingTests.swift   # NEW — unit tests for helper functions
└── SwiftUIViewSnapshotTests.swift  # MODIFIED — snapshot tests for new views
```

**Structure Decision**: Feature code lives in the existing `TextMessageField/` directory following the project's file-per-component pattern. Pure formatting logic is extracted to `Helpers/` for testability.

## Complexity Tracking

No constitution violations — table not needed.
