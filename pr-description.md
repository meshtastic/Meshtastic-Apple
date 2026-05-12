## What changed?

Adds **message formatting toolbar** (iOS 18+) and **link styling** for message bubbles.

### Message Formatting Toolbar (iOS 18+)

A markdown formatting toolbar in the message compose UI. Users type/see raw markdown; a live preview shows rendered output. Gated to iOS 18+ / macOS 15+ — iOS 17 users see the unchanged compose field.

- **Bold**, **Italic**, **Strikethrough**, **Code**, and **Link** formatting buttons in a compact scrollable toolbar row
- Select text + tap to wrap with delimiters; tap again to toggle off
- Tap with collapsed cursor to insert delimiter pairs and type between them
- Link button opens a URL entry dialog; wraps selection as `[text](url)`
- Live preview bubble above compose field (hidden when no markdown present)
- Markdown rendered in channel/user message list previews
- Mac Catalyst: Enter sends, Shift+Enter inserts line break; character palette retained

### Link Styling in Message Bubbles

- Links in message bubbles (URLs, Meshtastic channel/contact links, markdown links) now use the **design standards v1.4 Link color** (Blue 400 `#9BA8E0`) with underline styling
- `MeshtasticLink` color asset updated to Blue 400 `#9BA8E0` (same value for light and dark mode per design standards v1.4)
- `MessageText.underlineLinks(in:)` sets both `foregroundColor` and `underlineStyle` on `AttributedString` link runs
- `.tint` modifier on message bubbles uses `MeshtasticLink` for consistency

### Files Changed

| File | Change |
|------|--------|
| `Meshtastic/Views/Messages/MessageText.swift` | Link color → `MeshtasticLink`, underline styling via `underlineLinks(in:)` |
| `Meshtastic/Assets.xcassets/Colors/MeshtasticLink.colorset/Contents.json` | Updated to Blue 400 `#9BA8E0` per design standards v1.4 |
| `Meshtastic/Views/Messages/TextMessageField/TextMessageField.swift` | Formatting toolbar, live preview, Mac Catalyst Enter key handling |
| `specs/004-message-formatting-toolbar/spec.md` | Added FR-031 for link color styling |
| `docs/user/messages.md` | Added Link Appearance section with screenshot |
| `MeshtasticTests/SwiftUIViewSnapshotTests.swift` | Added `MessageTextLink` snapshot tests (light + dark) |

## Why did it change?

1. **Formatting toolbar**: Users had no way to format messages with bold, italic, etc. without manually typing markdown syntax. The toolbar makes formatting discoverable and accessible.
2. **Link styling**: Links in message bubbles were visually indistinct from regular text, making them hard to identify as tappable. The design standards v1.4 introduced a dedicated Link color token (Blue 400 `#9BA8E0`) which provides clear visual distinction with WCAG-compliant contrast.

## How is this tested?

- **Snapshot tests**: `MessageTextLinkSnapshotTests` — light and dark mode snapshots of link-styled message bubbles; `MessagePreviewSnapshotTests` — formatting toolbar, bold preview, mixed preview, compose area
- **Manual testing**: Verified link color rendering on device in both light and dark mode; tested URL tapping for external links, Meshtastic channel URLs, and contact URLs; verified formatting toolbar on iOS 18 and fallback on iOS 17

## Screenshots/Videos (when applicable)

<!-- Attach screenshots of: link-styled message bubbles (light + dark), formatting toolbar -->

## Checklist

- [x] My code adheres to the project's coding and style guidelines.
- [x] I have conducted a self-review of my code.
- [x] I have commented my code, particularly in complex areas.
- [x] I have verified whether these changes require an update to existing documentation or if new documentation is needed, and created an issue in the [docs repo](http://github.com/meshtastic/meshtastic/issues) if applicable.
- [x] I have tested the change to ensure that it works as intended.
