# Quickstart: Link Formatting (FR-025 – FR-030)

## Files to Modify

| File | Changes |
|---|---|
| `Meshtastic/Helpers/MarkdownFormatting.swift` | Add `.link` to `MarkdownStyle`, add `wrapSelectionWithLink()`, `unwrapLink()`, `isMarkdownLink()`, update `containsMarkdownSyntax()` |
| `Meshtastic/Views/Messages/TextMessageField/FormattingToolbarButtons.swift` | Add `@State` for link dialog, handle `.link` case in `applyFormatting()`, add `.alert` modifier, update accessibility label |
| `MeshtasticTests/MarkdownFormattingTests.swift` | Add test suite for link wrap/unwrap/detect/placeholder |

## No Files to Create

All changes fit within existing files.

## Implementation Order

1. **MarkdownFormatting.swift** — Add `.link` enum case + 3 new functions + update `containsMarkdownSyntax`
2. **FormattingToolbarButtons.swift** — Add link dialog state, special-case link button tap, add `.alert` modifier
3. **MarkdownFormattingTests.swift** — Add `LinkFormattingTests` suite

## Build & Test

```bash
# Build (Xcode)
xcodebuild build -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 16'

# Test
xcodebuild test -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 16'
```
