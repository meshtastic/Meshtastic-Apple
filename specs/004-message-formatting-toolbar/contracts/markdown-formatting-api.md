# Contract: Markdown Formatting API

**Feature**: 004-message-formatting-toolbar
**Date**: 2026-05-10
**Scope**: Internal Swift API — `MarkdownFormatting` helper functions

This contract defines the public interface of the `MarkdownFormatting` helper module. These are pure functions with no side effects, operating on `String` + `Range<String.Index>` inputs. All functions are testable in isolation.

## Types

### MarkdownStyle

```swift
enum MarkdownStyle: CaseIterable {
    case bold
    case italic
    case strikethrough
    case code

    var openingDelimiter: String { ... }
    var closingDelimiter: String { ... }
    var sfSymbol: String { ... }
}
```

| Case | `openingDelimiter` | `closingDelimiter` | `sfSymbol` |
|------|--------------------|--------------------|------------|
| `.bold` | `"**"` | `"**"` | `"bold"` |
| `.italic` | `"*"` | `"*"` | `"italic"` |
| `.strikethrough` | `"~~"` | `"~~"` | `"strikethrough"` |
| `.code` | `` "`" `` | `` "`" `` | `"chevron.left.forwardslash.chevron.right"` |

### FormattingResult

```swift
struct FormattingResult {
    let text: String
    let selectedRange: Range<String.Index>
}
```

## Functions

### wrapSelection

Wraps the substring at the given range with the style's delimiters, or removes them if already wrapped (toggle behaviour).

```swift
func wrapSelection(
    in text: String,
    range: Range<String.Index>,
    style: MarkdownStyle
) -> FormattingResult
```

**Preconditions**:
- `range` must be valid within `text`.
- `range` must be non-empty (for selection wrapping; use `insertDelimiters` for cursor-only).

**Behaviour**:
- If the substring at `range` is already enclosed by the style's delimiters (immediately adjacent), **removes** them (toggle off).
- Otherwise, **inserts** opening delimiter before `range.lowerBound` and closing delimiter after `range.upperBound`.

**Returns**: `FormattingResult` with:
- `.text` — the modified string.
- `.selectedRange` — range spanning the content between delimiters (excluding delimiters themselves) for cursor repositioning.

**Examples**:
| Input text | Range | Style | Output text | Output range content |
|------------|-------|-------|-------------|---------------------|
| `"hello world"` | `"world"` | `.bold` | `"hello **world**"` | `"world"` |
| `"hello **world**"` | `"world"` (inner) | `.bold` | `"hello world"` | `"world"` |
| `"hello world"` | `"world"` | `.code` | `` "hello `world`" `` | `"world"` |

---

### insertDelimiters

Inserts opening + closing delimiters at a cursor position (empty selection) and returns the cursor position between them.

```swift
func insertDelimiters(
    in text: String,
    at index: String.Index,
    style: MarkdownStyle
) -> FormattingResult
```

**Preconditions**:
- `index` must be valid within `text` (including `text.endIndex`).

**Behaviour**:
- Inserts `openingDelimiter + closingDelimiter` at `index`.
- Cursor is positioned between the delimiters.

**Returns**: `FormattingResult` with:
- `.text` — the modified string.
- `.selectedRange` — an empty range positioned between the two delimiters.

**Examples**:
| Input text | Index | Style | Output text | Cursor position |
|------------|-------|-------|-------------|-----------------|
| `"hello "` | end | `.bold` | `"hello ****"` | between 2nd and 3rd `*` |
| `""` | start | `.italic` | `"**"` | between the two `*` |

---

### isStyleActive

Detects whether the cursor or selection is currently inside a pair of delimiters for the given style.

```swift
func isStyleActive(
    in text: String,
    range: Range<String.Index>,
    style: MarkdownStyle
) -> Bool
```

**Preconditions**:
- `range` must be valid within `text`.
- `range` may be empty (cursor) or non-empty (selection).

**Behaviour**:
- Searches backward from `range.lowerBound` for the opening delimiter.
- Searches forward from `range.upperBound` for the closing delimiter.
- Returns `true` only if a matched pair is found enclosing the range.
- For bold vs italic disambiguation: checks for `**` before `*` to avoid false positives.

**Returns**: `true` if the cursor/selection is enclosed by the style's delimiters.

---

### containsMarkdownSyntax

Determines whether a string contains any markdown formatting syntax, used to show/hide the live preview.

```swift
func containsMarkdownSyntax(_ text: String) -> Bool
```

**Behaviour**:
- Returns `true` if `text` contains any of: `**`, `*`, `~~`, `` ` ``.
- Simple character-presence check — not a full markdown parse.
- Returns `false` for empty strings.

---

## View Contracts

### FormattingToolbarButtons

A SwiftUI view rendering the four formatting buttons in an `HStack`.

**Inputs**:
- `typingMessage: Binding<String>` — the raw compose text
- `textSelection: Binding<TextSelection?>` — the current cursor/selection state

**Outputs** (side effects via bindings):
- Mutates `typingMessage` to insert/remove delimiters
- Mutates `textSelection` to reposition cursor after formatting

**Accessibility**:
- Each button has an accessibility label matching its style name ("Bold", "Italic", "Strikethrough", "Code")
- Minimum 44×44pt touch target (FR-006)

### MessagePreview

A SwiftUI view rendering the live markdown preview below the compose field.

**Inputs**:
- `text: String` — the raw markdown text to preview

**Visibility**:
- Hidden when `containsMarkdownSyntax(text)` returns `false`
- Visible otherwise

**Rendering**:
- `Text(LocalizedStringKey(text))` styled to resemble a sent message bubble
