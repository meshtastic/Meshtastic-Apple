# Data Model: Message Formatting Toolbar

**Feature**: 004-message-formatting-toolbar
**Date**: 2026-05-10

## Schema Changes

**None.** This feature requires no SwiftData schema changes. The raw markdown string is stored in the existing `messagePayload` field and rendered via the existing `messagePayloadMarkdown` / `displayedMarkdownPayload` pipeline.

## Entities

### Existing Entities (unchanged)

#### MessageEntity

| Field | Type | Role in This Feature |
|-------|------|---------------------|
| `messagePayload` | `String?` | Stores the raw message text including user-typed markdown delimiters (e.g., `**bold**`). This is the source of truth — no transformation occurs before storage. |
| `messagePayloadMarkdown` | `String?` | Stores the result of `generateMessageMarkdown()` applied to `messagePayload` — adds link/phone/address markdown on top of user-typed formatting. Computed at send time. |
| `messagePayloadTranslated` | `String?` | Translation of `messagePayload`. Unchanged by this feature. |
| `messagePayloadTranslatedMarkdown` | `String?` | Translation with markdown links applied. Unchanged by this feature. |
| `displayedMarkdownPayload` | `String` (computed) | Returns the appropriate markdown string for rendering based on translation state. Unchanged by this feature. |

**Data flow** (send path):
```
typingMessage (raw markdown, e.g., "**hello** world")
    │
    ├──► accessoryManager.sendMessage(message: typingMessage)
    │        │
    │        ├──► MessageEntity.messagePayload = typingMessage
    │        └──► MessageEntity.messagePayloadMarkdown = generateMessageMarkdown(typingMessage)
    │
    └──► Wire: protobuf payload contains raw markdown string
```

**Data flow** (render path):
```
MessageEntity.displayedMarkdownPayload
    │
    └──► Text(LocalizedStringKey(payload))
              │
              └──► SwiftUI renders **bold**, *italic*, ~~strike~~, `code`
```

## New Types (view-layer only, not persisted)

### MarkdownStyle

A value type representing one of the four supported inline formatting styles. Used by the toolbar buttons and the formatting helper functions.

```
enum MarkdownStyle: CaseIterable {
    case bold
    case italic
    case strikethrough
    case code
}
```

| Case | Opening Delimiter | Closing Delimiter | SF Symbol | Byte Cost |
|------|-------------------|-------------------|-----------|-----------|
| `bold` | `**` | `**` | `bold` | 4 bytes |
| `italic` | `*` | `*` | `italic` | 2 bytes |
| `strikethrough` | `~~` | `~~` | `strikethrough` | 4 bytes |
| `code` | `` ` `` | `` ` `` | `chevron.left.forwardslash.chevron.right` | 2 bytes |

### Formatting Helper Result

The return type from wrap/unwrap operations, providing the mutated string and the new cursor/selection range.

```
struct FormattingResult {
    let text: String
    let selectedRange: Range<String.Index>
}
```

## State Ownership

All formatting state is **transient and view-local** — nothing is persisted beyond what already exists in `MessageEntity`.

| State | Owner | Type | Lifecycle |
|-------|-------|------|-----------|
| `typingMessage` | `TextMessageField` | `@State String` | Cleared on send |
| `textSelection` | `TextMessageField` | `@State TextSelection?` | Managed by SwiftUI `TextEditor` binding |
| `totalBytes` | `TextMessageField` | `@State Int` | Recomputed on every `typingMessage` change |
| Active style detection | Computed | Derived from `typingMessage` + `textSelection` | Recalculated per render cycle |

## Validation Rules

| Rule | Source | Enforcement |
|------|--------|-------------|
| Message ≤ 200 bytes (UTF-8) | Existing FR-014 | `onChange` handler drops trailing characters |
| Delimiter insertion respects byte limit | FR-014 | Same `onChange` handler — if wrapping exceeds limit, trailing chars are trimmed |
| Empty message cannot be sent | Existing behaviour | Send button hidden when `typingMessage.isEmpty` |

## State Transitions

No state machine — the compose field is a simple text-in / text-out flow:

```
[Empty] ──type──► [Has Text] ──format──► [Has Markdown Text] ──send──► [Empty]
                      │                         │
                      └─────────send─────────────┘
```

The live preview is a pure function of `typingMessage`:
- `containsMarkdownDelimiters(typingMessage)` → show/hide preview
- `Text(LocalizedStringKey(typingMessage))` → render preview content
