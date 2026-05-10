# Research: Message Formatting Toolbar (Pure SwiftUI)

**Feature**: 004-message-formatting-toolbar
**Date**: 2026-05-10

## Research Tasks & Findings

### 1. TextEditor(text:selection:) API on iOS 18+ / macOS 15+

**Task**: Verify that `TextEditor(text:selection:)` with a `TextSelection?` binding is available and stable on iOS 18.0+ / macOS 15.0+.

**Decision**: Use `TextEditor(text:selection:)` gated behind `if #available(iOS 18.0, macOS 15.0, *)`.

**Rationale**: The `TextEditor` initialiser accepting a `Binding<TextSelection?>` was introduced in iOS 18.0 / macOS 15.0 as part of Apple's SwiftUI text editing improvements. It provides:
- `TextSelection.Selection` — an enum with `.range(Range<String.Index>)` for text selections and cursor positions.
- Read/write access to the selection, enabling programmatic cursor placement after delimiter insertion.
- The `TextSelection` type surfaces selection indices as `String.Index` values relative to the bound `text` string, making substring manipulation straightforward.

**Alternatives considered**:
- `UIViewRepresentable` wrapping `UITextView` — rejected per FR-020 (no UIKit views permitted) and Constitution Principle I.
- Tracking cursor position via `onChange` heuristics — rejected as unreliable and fragile.
- `@FocusState` with `TextField` — rejected because `TextField` does not expose selection range.

### 2. TextSelection — Extracting Cursor Position and Selection Range

**Task**: Determine how to extract a usable `Range<String.Index>` from `TextSelection?` to implement delimiter wrapping.

**Decision**: Pattern-match on `textSelection?.selection` to extract the range.

**Rationale**: `TextSelection` has a `selection` property of type `TextSelection.Selection?`. The enum cases are:
- `.range(Range<String.Index>)` — represents both cursor position (empty range where `lowerBound == upperBound`) and text selection (non-empty range).

To detect cursor-only vs selection:
```swift
guard let selection = textSelection?.selection else { return }
switch selection {
case .range(let range):
    if range.isEmpty {
        // Cursor at range.lowerBound, no selection — insert delimiters
    } else {
        // Text selected — wrap substring
    }
}
```

After mutation, set `textSelection = TextSelection(range: newRange)` to reposition the cursor.

**Alternatives considered**:
- Using `UITextRange` via UIKit bridge — rejected (no UIKit).
- Inferring selection from string diffs — rejected as unreliable.

### 3. TextEditor Visual Matching with Existing TextField

**Task**: Ensure the `TextEditor` replacement visually matches the current `TextField` appearance.

**Decision**: Apply identical styling modifiers to `TextEditor` as currently used on `TextField`.

**Rationale**: The current `TextField` in `TextMessageField.swift` uses:
- `.frame(minHeight: 36)` for minimum height
- `.padding(.horizontal, 16)` and `.padding(.vertical, 12)` for internal padding
- `RoundedRectangle(cornerRadius: 20)` stroke border (`.tertiary`, lineWidth 1) with filled background
- `.foregroundColor(.primary)` for text colour
- `.multilineTextAlignment(.leading)` for alignment

`TextEditor` supports all these modifiers. Key differences to address:
- `TextEditor` has a default opaque background — override with `.scrollContentBackground(.hidden)` to allow the custom `RoundedRectangle` background to show through.
- `TextEditor` does not have the `axis: .vertical` auto-expansion behaviour of `TextField` — it natively supports multiline and grows with content, but may need `.frame(minHeight: 36)` and no fixed maxHeight to match.
- `TextEditor` does not support `onSubmit` — on Mac Catalyst, Return/Enter should be handled differently (e.g., via `.onKeyPress` or by checking for newline characters in `onChange`).

**Alternatives considered**: None — this is the only approach that satisfies FR-003 (visual match) with pure SwiftUI.

### 4. Markdown Delimiter Wrapping/Unwrapping Logic

**Task**: Design the string manipulation logic for wrapping selected text with markdown delimiters and toggling them off.

**Decision**: Create a `MarkdownFormatting` helper with pure functions that operate on `String` + `Range<String.Index>`.

**Rationale**: The formatting operations are:

| Style | Opening | Closing | SF Symbol |
|-------|---------|---------|-----------|
| Bold | `**` | `**` | `bold` |
| Italic | `*` | `*` | `italic` |
| Strikethrough | `~~` | `~~` | `strikethrough` |
| Code | `` ` `` | `` ` `` | `chevron.left.forwardslash.chevron.right` |

**Wrap with selection** (FR-008): Replace substring at range with `opening + substring + closing`. Return the new range spanning the inserted content (excluding delimiters) for cursor repositioning.

**Toggle off** (FR-009): Detect if the characters immediately before and after the selection match the delimiter. If so, remove them. Detection checks:
- Characters at `text[range.lowerBound - delimiter.count ..< range.lowerBound]` match opening delimiter
- Characters at `text[range.upperBound ..< range.upperBound + delimiter.count]` match closing delimiter

**Insert at cursor** (FR-010): Insert `opening + closing` at cursor position. Return a new cursor position between the delimiters.

**Bold+Italic overlap** (FR-017): When wrapping already-bold text with italic (or vice versa), the result should be `***text***`. The wrapping logic naturally handles this — wrapping `**text**` with `*...*` produces `***text***`.

**Alternatives considered**:
- Regex-based detection — rejected as overcomplicated for symmetric delimiters.
- `NSAttributedString` transformation — rejected per FR-020.

### 5. Active State Detection for Toolbar Buttons (FR-007)

**Task**: Determine how to detect whether the cursor is inside existing delimiters to show active button state.

**Decision**: Scan outward from the cursor position in the raw string to find matching delimiter pairs.

**Rationale**: For each formatting style, check if the cursor (or selection) is enclosed by the style's delimiters:
1. Search backward from `range.lowerBound` for the opening delimiter.
2. Search forward from `range.upperBound` for the closing delimiter.
3. If both are found and they form a valid pair (no unmatched delimiters between them), the style is active.

Special care for bold vs italic ambiguity:
- `***text***` means both bold and italic are active.
- `**text**` means only bold is active.
- `*text*` means only italic is active.
- Detection prioritises the longer delimiter first: check for `**` before `*`.

This logic is O(n) where n is the message length — well within the 200-byte limit performance requirement.

**Alternatives considered**:
- Full markdown parser — rejected as overkill for 4 inline styles with a 200-byte message limit.
- Regex matching — viable but less readable; simple string scanning is sufficient.

### 6. Live Preview Rendering (FR-011, FR-012)

**Task**: Confirm that `Text(LocalizedStringKey(rawMarkdown))` renders standard markdown correctly in SwiftUI.

**Decision**: Use `Text(LocalizedStringKey(typingMessage))` for the preview, consistent with the existing rendering path in `MessageText.swift`.

**Rationale**: SwiftUI's `Text` with `LocalizedStringKey` renders markdown since iOS 15:
- `**bold**` → bold text ✅
- `*italic*` → italic text ✅
- `~~strikethrough~~` → strikethrough text ✅
- `` `code` `` → monospaced text ✅

This is the same rendering path used in `MessageText.swift` via `message.displayedMarkdownPayload` → `LocalizedStringKey(...)`. No additional rendering infrastructure is needed.

**Preview visibility** (FR-012): Check if `typingMessage` contains any markdown delimiter characters (`**`, `*`, `~~`, `` ` ``). A simple heuristic: if the string contains at least one of `*`, `~`, or `` ` `` characters, show the preview. This avoids false negatives while keeping the check trivial.

A more precise check would be to compare `typingMessage` with its rendered output — but since `Text(LocalizedStringKey(...))` is a view, not a string, we cannot diff directly. The character-presence heuristic is acceptable because showing a preview for a message that happens to contain `*` in non-markdown context is harmless.

**Alternatives considered**:
- `AttributedString(markdown:)` for preview — viable but adds complexity; `LocalizedStringKey` is already proven in the codebase.
- WKWebView for rendering — rejected per FR-020 (no UIKit).

### 7. Integration with Existing Message Pipeline

**Task**: Verify that raw markdown strings flow correctly through `sendMessage()` → persistence → rendering.

**Decision**: No changes to the message pipeline. Raw markdown is already the wire format.

**Rationale**:
- `TextMessageField.sendMessage()` passes `typingMessage` directly to `accessoryManager.sendMessage(message:...)`.
- `AccessoryManager+ToRadio.swift` stores `message` in `messagePayload` and `generateMessageMarkdown(message:)` in `messagePayloadMarkdown`. Both continue to work correctly because the message is already a markdown string by the time it reaches `sendMessage()`.
- `generateMessageMarkdown()` in `MeshPackets.swift` detects URLs, phone numbers, and addresses and wraps them in markdown links. This post-processing still applies correctly to the markdown string — the formatting delimiters (`**`, `*`, etc.) do not interfere with `NSDataDetector` pattern matching because the detector operates on content text, not delimiters.
- On the receiving side, `MessageText.swift` renders via `Text(LocalizedStringKey(message.displayedMarkdownPayload))` — the existing path handles any valid markdown.
- Recipients on older OS versions (iOS 17.x) also render markdown via the same `LocalizedStringKey` path (SwiftUI has rendered markdown in `Text` since iOS 15), so SC-006 (cross-version rendering) is satisfied.

### 8. Mac Catalyst Considerations (FR-018)

**Task**: Ensure the character palette button is preserved on Mac Catalyst while adding formatting buttons.

**Decision**: Use `#if targetEnvironment(macCatalyst)` conditional compilation to include the character palette button alongside the formatting buttons.

**Rationale**: The existing toolbar in `TextMessageField.swift` already uses `#if targetEnvironment(macCatalyst)` to conditionally show the emoji/character palette button. The formatting buttons will be added before the existing buttons in the same `HStack`. The toolbar layout on Mac Catalyst will be: `[Bold] [Italic] [Strikethrough] [Code] [Spacer] [CharPalette] [Alert] [RequestPosition] [TextMessageSize]`.

### 9. Mac Catalyst Enter-to-Send Behaviour

**Task**: Determine how to handle Enter-to-send on Mac Catalyst since `TextEditor` does not support `.onSubmit`.

**Decision**: Use `.onKeyPress(.return)` (iOS 17+) to intercept the Return key on Mac Catalyst and trigger `sendMessage()`.

**Rationale**: `TextField` supports `.onSubmit` for Enter-to-send, but `TextEditor` inserts a newline on Return by default. On Mac Catalyst, the expected behaviour is that pressing Return sends the message (matching the current `TextField` behaviour). Options:
- `.onKeyPress(.return)` — available on iOS 17+ / macOS 14+. Since our `TextEditor` path is iOS 18+ only, this is always available. We can intercept Return, call `sendMessage()`, and return `.handled` to prevent newline insertion.
- `onChange` monitoring for `\n` — fragile and would require removing the newline after detection.

`.onKeyPress(.return)` is the clean solution. It's only needed on Mac Catalyst — on iOS, the keyboard Return key is fine for inserting newlines (send is via the send button).

### 10. Byte Limit Enforcement (FR-014)

**Task**: Confirm the 200-byte limit enforcement works unchanged with `TextEditor`.

**Decision**: The existing `onChange` handler logic applies identically to `TextEditor`.

**Rationale**: The current implementation:
```swift
.onChange(of: typingMessage) { _, value in
    totalBytes = value.utf8.count
    while totalBytes > Self.maxbytes {
        typingMessage = String(typingMessage.dropLast())
        totalBytes = typingMessage.utf8.count
    }
}
```
This works identically on both `TextField` and `TextEditor` since both bind to the same `typingMessage: String`. When formatting delimiters are inserted (adding 2-4 bytes per style), the `onChange` handler truncates if the total exceeds 200 bytes. The truncation drops from the end, which may remove closing delimiters — this is acceptable per the spec's edge case note.
