# Feature Specification: Message Formatting Toolbar (Pure SwiftUI)

**Feature Branch**: `004-message-formatting-toolbar`  
**Created**: 2026-05-10  
**Updated**: 2026-05-11  
**Status**: Draft (Updated — added link formatting support)  
**Input**: User description: "Add a markdown formatting toolbar to the message compose UI. Pure SwiftUI approach — user types/sees raw markdown, live preview shows rendered output. Gated to iOS 18+ / macOS 15+ only."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Apply Formatting to Selected Text (Priority: P1)

A user on iOS 18+ is composing a mesh message and wants to emphasise part of their text. They type a message in the compose field, select a word or phrase, then tap one of the formatting buttons (Bold, Italic, Strikethrough, or Code) in the keyboard toolbar. The raw markdown delimiters are inserted around the selected text (e.g., `**word**`), and the live preview below the compose field immediately shows the rendered result. The user sends the message, and the recipient sees the formatted text rendered in their message bubble.

**Why this priority**: This is the core formatting interaction — wrapping selected text with markdown delimiters. Without it, the toolbar buttons have no purpose. All other stories depend on this working correctly.

**Independent Test**: Can be fully tested by typing text in the compose field, selecting a word, tapping Bold, verifying (a) the raw text now shows `**word**` in the compose field, (b) the live preview renders the word in bold, and (c) the sent message renders bold in the recipient's bubble.

**Acceptance Scenarios**:

1. **Given** a user on iOS 18+ has typed text in the compose field and selected a word, **When** they tap the Bold button, **Then** the selected word is wrapped with `**` delimiters in the raw text (e.g., `hello` becomes `**hello**`) and the live preview shows it bold.
2. **Given** a user has wrapped a word with `**` delimiters, **When** they select the inner text (excluding delimiters) and tap Bold again, **Then** the `**` delimiters are removed (toggle off) and the preview updates.
3. **Given** a user applies Italic formatting to selected text, **When** the text is wrapped, **Then** single `*` delimiters surround the selection and the preview shows italic text.
4. **Given** a user applies Strikethrough formatting, **When** the text is wrapped, **Then** `~~` delimiters surround the selection and the preview shows strikethrough text.
5. **Given** a user applies Code formatting, **When** the text is wrapped, **Then** backtick delimiters surround the selection and the preview shows monospaced text.
6. **Given** a user is on iOS 17.x, **When** they open the message compose field, **Then** the compose field and toolbar are identical to the existing unformatted experience — no formatting buttons and no TextEditor appear.

---

### User Story 2 - Insert Formatting Delimiters at Cursor (Priority: P2)

A user wants to type formatted text from scratch. With a collapsed cursor (no selection) in the compose field, they tap a formatting button. The appropriate opening and closing delimiters are inserted at the cursor position, and the cursor is placed between them so the user can immediately type formatted content.

**Why this priority**: Enables the "format-then-type" workflow, which is the second most common formatting pattern after "select-then-format."

**Independent Test**: Can be fully tested by placing the cursor in the compose field, tapping Italic, verifying `**` is inserted with the cursor between the two `*` characters, typing text, and confirming the preview shows italic rendering.

**Acceptance Scenarios**:

1. **Given** the cursor is at position N with no selection, **When** the user taps Bold, **Then** `****` is inserted at position N and the cursor is placed between the second and third `*` (between the opening and closing `**`).
2. **Given** the cursor is at position N with no selection, **When** the user taps Italic, **Then** `**` is inserted and the cursor is placed between the two `*` characters.
3. **Given** the cursor is at position N with no selection, **When** the user taps Code, **Then** two backticks are inserted and the cursor is placed between them.
4. **Given** delimiters have been inserted at cursor, **When** the user types characters, **Then** the typed text appears between the delimiters and the preview renders it with the chosen style.

---

### User Story 3 - Live Preview of Formatted Message (Priority: P2)

A user is composing a message that contains markdown syntax. Below the compose field, a small read-only preview appears showing how the message will look when rendered. This gives the user real-time visual feedback without requiring them to send the message first.

**Why this priority**: The preview is what bridges the gap between raw markdown input and user comprehension — without it, users unfamiliar with markdown cannot verify their formatting is correct.

**Independent Test**: Can be fully tested by typing `**hello** world` in the compose field and verifying the preview shows "**hello** world" with "hello" rendered bold.

**Acceptance Scenarios**:

1. **Given** the compose field contains text with markdown syntax (e.g., `**bold**`), **When** the user views the compose area, **Then** a preview appears below the compose field showing the rendered markdown.
2. **Given** the compose field contains plain text with no markdown syntax, **When** the user views the compose area, **Then** no preview is shown (the preview area is hidden).
3. **Given** the user is typing and adding/removing markdown syntax, **When** the text changes, **Then** the preview updates in real time to reflect the current rendered appearance.
4. **Given** the preview is visible, **Then** it is styled to resemble a sent message bubble so the user understands how the message will appear to recipients.
5. **Given** the preview is visible, **Then** it is read-only and cannot be edited or interacted with.

---

### User Story 4 - Combined Bold+Italic Formatting (Priority: P3)

A user wants to apply both bold and italic to the same text. They can either apply bold first and then italic (or vice versa), resulting in `***text***` triple-star syntax.

**Why this priority**: Edge case for power users — the core bold and italic features must work independently first.

**Independent Test**: Can be fully tested by selecting text, tapping Bold, then selecting the bold text and tapping Italic, and verifying `***text***` appears with both styles rendered in the preview.

**Acceptance Scenarios**:

1. **Given** selected text is already wrapped with `**` (bold), **When** the user selects the entire bold span including its `**` delimiters and taps Italic, **Then** the text is wrapped with `***` (triple-star) and the preview shows bold italic.
2. **Given** text is wrapped with `***`, **When** the user selects it and taps Bold, **Then** the bold delimiters are removed leaving `*text*` (italic only).

---

### User Story 5 - Link Formatting (Priority: P2)

A user on iOS 18+ is composing a mesh message and wants to insert a hyperlink. They select a word or phrase in the compose field, then tap the Link button in the formatting toolbar. A dialog appears with a text field for entering a URL and Confirm/Cancel buttons. The user types a URL and taps Confirm. The selected text is wrapped in markdown link syntax `[selected text](url)`, and the live preview shows a rendered link. If the user taps Cancel, no changes are made.

**Why this priority**: Links are a natural complement to inline text formatting — users frequently share URLs in mesh messages. This completes the formatting toolbar's coverage of common markdown inline syntax.

**Independent Test**: Can be fully tested by typing text in the compose field, selecting a word, tapping the Link button, entering a URL in the dialog, tapping Confirm, and verifying (a) the raw text shows `[word](https://example.com)` in the compose field, (b) the live preview renders a clickable-style link, and (c) the sent message renders the link in the recipient's bubble.

**Acceptance Scenarios**:

1. **Given** a user on iOS 18+ has typed text and selected a word, **When** they tap the Link button, **Then** a dialog/sheet appears with a URL text field and Confirm/Cancel buttons.
2. **Given** the link dialog is open with a non-empty URL entered, **When** the user taps Confirm, **Then** the selected text is wrapped in `[selected text](url)` syntax in the raw text and the preview shows a rendered link.
3. **Given** the link dialog is open with an empty URL field, **When** the user views the Confirm button, **Then** the Confirm button is disabled (greyed out) — the user cannot confirm without entering a URL.
4. **Given** the link dialog is open, **When** the user taps Cancel, **Then** the dialog is dismissed and no changes are made to the compose field text or selection.
5. **Given** the cursor is at position N with no text selected, **When** the user taps the Link button and enters a URL and confirms, **Then** `[link text](url)` placeholder text is inserted at the cursor position.
6. **Given** selected text is already a markdown link matching `[text](url)` pattern, **When** the user selects the entire link span and taps the Link button, **Then** the link formatting is removed — only the display text portion is kept (e.g., `[hello](https://example.com)` becomes `hello`).
7. **Given** a user taps the Link button, **When** the dialog appears, **Then** the URL text field has keyboard focus so the user can immediately start typing.

---

### User Story 6 - iOS 17 Compatibility (Priority: P1)

Users on iOS 17.x (or macOS 14.x) see absolutely no change to their messaging experience. The existing TextField, keyboard toolbar, and message sending flow remain identical.

**Why this priority**: Equal priority to P1 because breaking the experience for existing users on older OS versions is unacceptable.

**Independent Test**: Can be tested by running the app on an iOS 17 simulator and verifying the compose UI is unchanged — no TextEditor, no formatting buttons, no preview.

**Acceptance Scenarios**:

1. **Given** a device running iOS 17.x, **When** the user opens the message compose field, **Then** the existing `TextField` is shown (not `TextEditor`).
2. **Given** a device running iOS 17.x, **When** the user views the keyboard toolbar, **Then** only the existing buttons appear (character palette on Mac Catalyst, AlertButton, RequestPositionButton, TextMessageSize) — no formatting buttons.
3. **Given** a device running iOS 17.x, **When** the user sends a message, **Then** the message sending flow is identical to the current implementation.

---

### Edge Cases

- What happens when the user applies formatting that would exceed the 200-byte limit? The byte limit is enforced on the raw `typingMessage` string. If wrapping with delimiters would exceed 200 bytes, the excess characters are trimmed as per existing behaviour (the `onChange` handler drops trailing characters).
- What happens when the user selects text that partially overlaps existing delimiters? When wrapping a selection that contains existing markdown delimiters, all existing delimiters within the selection are stripped first, then the new style's delimiters are applied. This prevents garbled/overlapping syntax (e.g., `~~**T~~e*st**` is impossible — the result is always clean).
- What happens when the compose field is empty and the user taps a formatting button? Formatting buttons are hidden until the user has typed at least 3 characters.
- What happens when the user pastes text containing markdown? The pasted text is treated as raw text — markdown in pasted content renders in the preview just like typed markdown.
- What happens with very long messages near the byte limit? The existing `onChange` truncation handles this — delimiter insertion that exceeds 200 bytes triggers the same drop-last-character logic.
- What happens when `TextSelection` is nil (e.g. before the user taps the editor)? Formatting buttons are disabled (greyed out) until the editor has focus and provides a valid `TextSelection`.
- What happens when the user selects only the inner text of a bold span and taps Italic? The italic delimiters wrap only the inner text — existing bold delimiters within the selection are stripped first, resulting in `*text*` (italic only). The preview shows the actual rendering so the user can verify.
- What happens when the user selects text that is partially inside a markdown link? If the selection partially overlaps a `[text](url)` pattern (e.g., only the display text or only the URL), the link button treats it as unformatted text and wraps the entire selection in new link syntax. The user can undo via standard text editing.
- What happens when the user enters a URL without a scheme (e.g., `example.com`)? The URL is inserted as-is — no automatic `https://` prefix is added. The raw markdown is preserved exactly as the user typed it.
- What happens when the link dialog is dismissed by swiping down (sheet) or tapping outside? The dialog is cancelled — no changes are made, same as tapping Cancel.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On iOS 18+ / macOS 15+, the compose field MUST use a SwiftUI `TextEditor` with the iOS 18 `selection:` binding (`TextSelection?`) to provide cursor and selection range access.
- **FR-002**: On iOS 17.x / macOS 14.x, the compose field MUST remain the existing `TextField` with no changes to appearance or behaviour.
- **FR-003**: The `TextEditor` MUST visually match the existing `TextField` appearance — same `RoundedRectangle(cornerRadius: 20)` border, padding (horizontal 16, vertical 4), same `.primary` foreground colour, and `.frame(minHeight: 36, maxHeight: 200)` for content-adaptive sizing.
- **FR-004**: Five formatting buttons MUST be displayed in a compact unified toolbar row on iOS 18+ (alongside Alert, Position, and byte counter): Bold (`bold` SF Symbol), Italic (`italic` SF Symbol), Strikethrough (`strikethrough` SF Symbol), Code (`chevron.left.forwardslash.chevron.right` SF Symbol), Link (`link` SF Symbol). Formatting buttons MUST only appear after the user has typed at least 3 characters. All toolbar controls (Alert bell, Position pin, byte counter) MUST use compact styling — icon-only with `.primary` foreground, no text labels.
- **FR-005**: Formatting buttons MUST be placed before the existing `AlertButton` in the toolbar row. The toolbar MUST scroll horizontally when its content exceeds the screen width. The byte counter MUST be right-aligned.
- **FR-006**: Each formatting button MUST meet the 44×36pt minimum touch target size.
- **FR-007**: *(Removed — active state pill indication was removed as too brittle with TextSelection index management.)*
- **FR-008**: When a formatting button is tapped with a non-empty text selection, the system MUST first expand the selection to include any adjacent markdown delimiter characters, strip all existing markdown delimiters from the expanded text, trim whitespace so delimiters hug content (trailing/leading spaces move outside delimiters), then wrap the cleaned text with the appropriate markdown delimiters (`**` for bold, `*` for italic, `~~` for strikethrough, `` ` `` for code). For the Link button, see FR-025 through FR-030. After wrapping, any orphaned (unpaired) delimiter characters remaining in the full text MUST be cleaned up. The resulting selection MUST expand to include the newly inserted delimiters (e.g., selecting `dolphin` and tapping Bold produces `**dolphin**` with the full `**dolphin**` selected). This prevents overlapping/garbled syntax and ensures correct markdown rendering.
- **FR-009**: When a formatting button is tapped with the inner text selected (excluding delimiters) on text already wrapped in the corresponding delimiters, the system MUST remove those delimiters (toggle off).
- **FR-010**: When a formatting button is tapped with a collapsed cursor (no selection), the system MUST insert opening and closing delimiters at the cursor position and place the cursor between them.
- **FR-011**: When the compose field contains markdown syntax, a read-only live preview MUST appear above the compose field, rendered using `Text(LocalizedStringKey(typingMessage))`.
- **FR-012**: When the compose field contains no markdown syntax, the live preview MUST be hidden.
- **FR-013**: The live preview MUST be styled to resemble a sent message bubble.
- **FR-014**: The byte limit (200 bytes) MUST be enforced on the raw `typingMessage` string using `typingMessage.utf8.count`. The existing `onChange` truncation logic applies unchanged.
- **FR-015**: On send, `typingMessage` (containing raw markdown syntax) MUST be passed directly to `accessoryManager.sendMessage()` with no conversion step.
- **FR-016**: Bold+italic overlap MUST use `***text***` (combined triple-star) syntax.
- **FR-017**: On Mac Catalyst, the existing character palette button MUST remain; formatting buttons MUST also be shown.
- **FR-018**: All formatting buttons MUST use SF Symbols exclusively — no styled text labels, no custom image assets.
- **FR-019**: No UIKit views are permitted — no `UIViewRepresentable`, no `UITextView`, no `NSAttributedString`. All UI MUST be pure SwiftUI.
- **FR-020**: Message list previews (ChannelList and UserList) MUST render markdown in the most-recent-message snippet using `Text(LocalizedStringKey(...))`.
- **FR-021**: On Mac Catalyst, pressing Enter in the `TextEditor` MUST send the message. Pressing Shift+Enter MUST insert a line break. The `onKeyPress(.return)` modifier MUST be placed on the parent `VStack` container, not on the `TextEditor` itself.
- **FR-022**: The toolbar MUST appear when the `TextEditor` gains focus and hide (with a 0.3-second delay) when it loses focus. Visibility is controlled by a `showToolbar` state variable updated via `onChange(of: isFocused)`.
- **FR-023**: On iOS 26+ / macOS 26+, the toolbar MUST use `.ultraThinMaterial` background in a `Capsule()` shape. On earlier versions, it MUST use a `Divider()` separator above and `.background(.bar)` for the toolbar row.
- **FR-024**: Formatting buttons MUST use `.buttonStyle(.plain)` to prevent SwiftUI's default button tinting from overriding the `.foregroundColor(.primary)` styling.
- **FR-025**: When the Link button is tapped with a non-empty text selection, a dialog/sheet MUST appear containing a text field for URL entry and Confirm/Cancel buttons.
- **FR-026**: The Confirm button in the link dialog MUST be disabled when the URL text field is empty. It MUST be enabled when the URL text field contains at least one character.
- **FR-027**: When the user confirms the link dialog with a non-empty URL, the selected text MUST be wrapped in markdown link syntax: `[selected text](entered url)`. The selection MUST update to include the full `[text](url)` span.
- **FR-028**: When the Link button is tapped with a collapsed cursor (no selection), the link dialog MUST still appear. On confirm, placeholder text `[link text](entered url)` MUST be inserted at the cursor position.
- **FR-029**: When the selected text matches the markdown link pattern `[text](url)`, tapping the Link button MUST remove the link formatting — replacing `[text](url)` with just `text` (the display text portion). No dialog is shown for this unwrap operation.
- **FR-030**: The Link button MUST use the `link` SF Symbol and MUST appear in the toolbar row alongside the existing four formatting buttons (after Code, before AlertButton).
- **FR-031**: Rendered links in message bubbles MUST use the design standards Link color (Blue 400 `#9BA8E0`) via the `MeshtasticLink` color asset, with `.underlineStyle(.single)` applied. The `underlineLinks(in:)` helper MUST set both `foregroundColor` and `underlineStyle` on every `AttributedString` run where `run.link != nil`. The `.tint` modifier on the message bubble MUST also use `MeshtasticLink` for consistency.

### Key Entities

- **typingMessage** (`String`): The raw message text including any markdown syntax characters. This is the single source of truth for both the compose field content and the transmitted message. No separate "formatted" or "attributed" representation exists.
- **TextSelection**: The SwiftUI iOS 18 type providing cursor position and selection range within the `TextEditor`. Used to determine where to insert/wrap delimiters. Updated after formatting operations to reflect the new selection (including delimiters).
- **MarkdownStyle**: A logical grouping (Bold, Italic, Strikethrough, Code, Link) each with its opening/closing delimiter strings and corresponding SF Symbol name. Link is a special case — it uses `[` / `](url)` syntax with a separate URL component rather than symmetric delimiters.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users on iOS 18+ can apply bold, italic, strikethrough, code, or link formatting to selected text in the compose field within a single tap (plus URL entry for links).
- **SC-002**: Users on iOS 18+ can see a real-time preview of their formatted message before sending, with preview updates appearing as they type.
- **SC-003**: Users on iOS 17.x experience zero changes to their message compose flow — the UI is identical to the pre-feature state.
- **SC-004**: 100% of formatting operations (wrap, unwrap, cursor-insert) complete without exceeding the 200-byte message limit or losing user text.
- **SC-005**: All five formatting styles (bold, italic, strikethrough, code, link) are accessible within the keyboard toolbar without requiring additional navigation or menus.
- **SC-006**: Formatted messages sent from iOS 18+ users render correctly in the recipient's message bubble on all supported OS versions (recipients do not need iOS 18+ to see rendered markdown).
- **SC-007**: Unit test coverage exists for all markdown wrapping/unwrapping helper functions: wrap with bold/italic/strikethrough/code, unwrap (toggle off), wrap at cursor (empty selection), delimiter boundary expansion, orphan cleanup, bold+italic triple-star combination, link wrapping with URL, link unwrapping, and link placeholder insertion.
- **SC-008**: Users can enter a URL and confirm link formatting within 3 taps (Link button → type URL → Confirm).

## Assumptions

- The iOS 18 `TextEditor(text:selection:)` initialiser with `TextSelection?` binding is available and stable for production use on iOS 18.0+ / macOS 15.0+.
- SwiftUI's `Text(LocalizedStringKey(typingMessage))` correctly renders standard markdown syntax (`**bold**`, `*italic*`, `~~strikethrough~~`, `` `code` ``) — this is the existing rendering path already used in `MessageText.swift`.
- Users are willing to see raw markdown syntax in the compose field with a separate preview, rather than WYSIWYG inline rendering.
- The existing 200-byte message limit is sufficient for messages with markdown delimiters (delimiters consume 2-4 bytes per formatted span).
- The `generateMessageMarkdown()` function in the message rendering pipeline handles URL/phone/address link wrapping independently and does not conflict with user-inserted markdown delimiters.
- `TextSelection` provides sufficient information (cursor index or selection range as `String.Index` values) to programmatically determine and manipulate the selected substring within `typingMessage`.

## Out of Scope

- Font size changes
- Text colour changes
- Images or attachments in messages
- Persisting formatting preferences across sessions
- WYSIWYG editing (user sees raw markdown; preview shows rendered output)
- Ordered/unordered lists, headings, or block-level markdown
- Custom keyboard or input accessory views built with UIKit
- URL validation beyond non-empty check (no scheme validation, no reachability check)
- Auto-detecting URLs in typed text and converting them to markdown links
- Link preview cards or URL metadata fetching
