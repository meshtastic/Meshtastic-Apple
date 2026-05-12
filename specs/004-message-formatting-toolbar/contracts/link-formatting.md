# Contracts: Link Formatting Functions

**Feature**: 004-message-formatting-toolbar (FR-025 – FR-030)

## Public API — `MarkdownFormatting.swift`

### `wrapSelectionWithLink(in:range:url:) -> FormattingResult`

```swift
/// Wraps selected text in markdown link syntax `[text](url)`.
/// If range is collapsed (empty), inserts `[link text](url)` placeholder.
func wrapSelectionWithLink(
    in text: String,
    range: Range<String.Index>,
    url: String
) -> FormattingResult
```

**Preconditions**: `url` is non-empty. `range` is valid within `text`.
**Postconditions**: Result text contains `[selectedText](url)`. Result selectedRange covers the full `[text](url)` span.

### `unwrapLink(in:range:) -> FormattingResult?`

```swift
/// If the selected text matches `[text](url)` pattern, removes link formatting
/// and returns the display text only. Returns nil if not a link.
func unwrapLink(
    in text: String,
    range: Range<String.Index>
) -> FormattingResult?
```

**Preconditions**: `range` is valid within `text`.
**Postconditions**: If match, result text has `[text](url)` replaced with `text`. If no match, returns nil.

### `isMarkdownLink(_:) -> Bool`

```swift
/// Returns true if the string matches the `[text](url)` markdown link pattern.
func isMarkdownLink(_ text: String) -> Bool
```

### `containsMarkdownSyntax(_:) -> Bool` (Updated)

Now also returns `true` for text containing `[text](url)` link patterns.

## UI Contract — `FormattingToolbarButtons`

### Link button behavior

1. **Tap with selection + text is NOT a link** → show `.alert` dialog with URL text field
2. **Tap with selection + text IS a link** → unwrap immediately (no dialog), per FR-029
3. **Tap with collapsed cursor** → show `.alert` dialog; on confirm insert `[link text](url)`
4. **Dialog Confirm** → disabled when URL field is empty (FR-026)
5. **Dialog Cancel / dismiss** → no changes to text (FR-025 scenario 4)
