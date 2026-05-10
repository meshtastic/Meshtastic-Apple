# Quickstart: Message Formatting Toolbar

**Feature**: 004-message-formatting-toolbar
**Branch**: `004-message-formatting-toolbar`

## Prerequisites

- Xcode (latest stable)
- iOS 18.0+ Simulator (to see formatting toolbar) and iOS 17.x Simulator (to test fallback)
- macOS 15.0+ (for Mac Catalyst testing)

## Getting Started

### 1. Switch to the feature branch

```bash
cd /path/to/Meshtastic-Apple
git checkout 004-message-formatting-toolbar
```

### 2. Open the project

```bash
open Meshtastic.xcodeproj
```

### 3. Build and run

Select an iOS 18+ simulator target and build (`⌘B`) / run (`⌘R`).

### 4. Test the feature

1. Connect to a Meshtastic device (or use the simulator with a mock connection).
2. Navigate to Messages → any channel or user conversation.
3. Tap the compose field to bring up the keyboard.
4. The toolbar row below the compose field should show: **[B] [I] [S] [</>]** followed by the existing Alert, Position, and Size buttons.
5. Type some text, select a word, tap Bold → verify `**word**` appears in the compose field.
6. Check the live preview below the compose field shows the word in bold.
7. Send the message — verify it renders with bold formatting in the chat bubble.

### 5. Test iOS 17 fallback

1. Switch to an iOS 17.x simulator target.
2. Build and run.
3. Navigate to the same message compose screen.
4. Verify: no formatting buttons, no `TextEditor`, no preview — identical to the existing experience.

## Key Files

| File | Purpose |
|------|---------|
| `Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift` | Main compose view — conditional `TextEditor` vs `TextField` |
| `Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift` | Four formatting button views |
| `Meshtastic/Views/Messages/TextMessageField/MessagePreview.swift` | Live markdown preview bubble |
| `Meshtastic/Helpers/MarkdownFormatting.swift` | Pure functions: wrap, unwrap, detect, insert delimiters |
| `MeshtasticTests/MarkdownFormattingTests.swift` | Unit tests for formatting helpers |

## Architecture at a Glance

```
TextMessageField (view)
├── if #available(iOS 18.0, macOS 15.0, *)
│   ├── TextEditor(text: $typingMessage, selection: $textSelection)
│   ├── MessagePreview(text: typingMessage)        ← visible if markdown detected
│   └── Toolbar HStack
│       ├── FormattingToolbarButtons(...)           ← NEW
│       ├── [Spacer]
│       ├── CharPalette (macCatalyst only)          ← EXISTING
│       ├── AlertButton                             ← EXISTING
│       ├── RequestPositionButton                   ← EXISTING
│       └── TextMessageSize                         ← EXISTING
└── else (iOS 17.x fallback)
    ├── TextField("Message", text: $typingMessage)  ← EXISTING, unchanged
    └── Toolbar HStack (existing buttons only)
```

## Running Tests

Tests are run via Xcode:
1. Select the `Meshtastic` scheme.
2. `⌘U` to run all tests.
3. New test files:
   - `MeshtasticTests/MarkdownFormattingTests.swift` — unit tests for wrap/unwrap/detect functions.
   - `MeshtasticTests/SwiftUIViewSnapshotTests.swift` — snapshot tests for `FormattingToolbarButtons` and `MessagePreview`.

## Common Issues

| Issue | Resolution |
|-------|------------|
| Formatting buttons don't appear | Ensure simulator is iOS 18.0+ — buttons are gated behind `#available` |
| `TextEditor` has white background | Add `.scrollContentBackground(.hidden)` modifier |
| Enter sends message on iOS but not Mac | `.onKeyPress(.return)` is only needed on Mac Catalyst; iOS uses the send button |
| Preview shows for plain text | Check `containsMarkdownSyntax()` — it should only trigger on `*`, `~`, or `` ` `` characters |
