# Feature Specification: Message Formatting Toolbar (Pure SwiftUI)

**Feature Branch**: `004-message-formatting-toolbar`  
**Created**: 2026-05-10  
**Status**: Draft (Re-specification — replaces WYSIWYG approach)  
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

### User Story 4 - Active Formatting State Indication (Priority: P3)

When the cursor is positioned inside existing markdown delimiters, the corresponding toolbar button visually indicates that the style is active. This helps users understand which formatting is applied at their current cursor position.

**Why this priority**: This is a polish/UX enhancement. The feature works without it, but it significantly improves discoverability and user confidence.

**Independent Test**: Can be fully tested by placing the cursor inside `**bold text**` and verifying the Bold button shows the active state (accent-filled pill background with white foreground).

**Acceptance Scenarios**:

1. **Given** the cursor is positioned between `**` and `**` delimiters, **When** the user views the toolbar, **Then** the Bold button displays an accent-filled pill background with white foreground icon.
2. **Given** the cursor is positioned between `*` and `*` (single) delimiters, **When** the user views the toolbar, **Then** the Italic button displays the active state.
3. **Given** the cursor is positioned outside any delimiters, **When** the user views the toolbar, **Then** all formatting buttons display their default (inactive) state.
4. **Given** the cursor is positioned inside nested `***` (bold+italic) delimiters, **When** the user views the toolbar, **Then** both Bold and Italic buttons display the active state.

---

### User Story 5 - Combined Bold+Italic Formatting (Priority: P3)

A user wants to apply both bold and italic to the same text. They can either apply bold first and then italic (or vice versa), resulting in `***text***` triple-star syntax.

**Why this priority**: Edge case for power users — the core bold and italic features must work independently first.

**Independent Test**: Can be fully tested by selecting text, tapping Bold, then selecting the bold text and tapping Italic, and verifying `***text***` appears with both styles rendered in the preview.

**Acceptance Scenarios**:

1. **Given** selected text is already wrapped with `**` (bold), **When** the user selects the entire bold span including its `**` delimiters and taps Italic, **Then** the text is wrapped with `***` (triple-star) and the preview shows bold italic.
2. **Given** text is wrapped with `***`, **When** the user selects it and taps Bold, **Then** the bold delimiters are removed leaving `*text*` (italic only).

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
- What happens when the user selects text that partially overlaps existing delimiters? The selection wrapping applies to exactly the selected substring — partial delimiter overlap results in nested/malformed markdown, which is acceptable as the preview shows the user exactly what will be sent.
- What happens when the compose field is empty and the user taps a formatting button? Delimiters are inserted at position 0 with the cursor between them.
- What happens when the user pastes text containing markdown? The pasted text is treated as raw text — markdown in pasted content renders in the preview just like typed markdown.
- What happens with very long messages near the byte limit? The existing `onChange` truncation handles this — delimiter insertion that exceeds 200 bytes triggers the same drop-last-character logic.
- What happens when `TextSelection` is nil (e.g. before the user taps the editor)? Formatting buttons are disabled (greyed out) until the editor has focus and provides a valid `TextSelection`.
- What happens when the user selects only the inner text of a bold span and taps Italic? The italic delimiters wrap only the inner text, producing `**_text_**` (nested), not `***text***` (triple-star). The preview shows the actual rendering so the user can verify. To get triple-star, the user must select the entire bold span including its `**` delimiters.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On iOS 18+ / macOS 15+, the compose field MUST use a SwiftUI `TextEditor` with the iOS 18 `selection:` binding (`TextSelection?`) to provide cursor and selection range access.
- **FR-002**: On iOS 17.x / macOS 14.x, the compose field MUST remain the existing `TextField` with no changes to appearance or behaviour.
- **FR-003**: The `TextEditor` MUST visually match the existing `TextField` appearance — same `RoundedRectangle(cornerRadius: 20)` border, same padding (horizontal 16, vertical 12), same `.primary` foreground colour, same multiline vertical growth.
- **FR-004**: Four formatting buttons MUST be added to the keyboard toolbar row on iOS 18+: Bold (`bold` SF Symbol), Italic (`italic` SF Symbol), Strikethrough (`strikethrough` SF Symbol), Code (`chevron.left.forwardslash.chevron.right` SF Symbol).
- **FR-005**: Formatting buttons MUST be placed before the existing `AlertButton` in the toolbar row.
- **FR-006**: Each formatting button MUST meet the 44×44pt minimum touch target size.
- **FR-007**: When a formatting button's style is active at the current cursor position, the button MUST display an accent-filled pill background with white foreground (iMessage-style toggle).
- **FR-008**: When a formatting button is tapped with a non-empty text selection, the system MUST wrap the selected substring with the appropriate markdown delimiters (`**` for bold, `*` for italic, `~~` for strikethrough, `` ` `` for code).
- **FR-009**: When a formatting button is tapped with the inner text selected (excluding delimiters) on text already wrapped in the corresponding delimiters, the system MUST remove those delimiters (toggle off).
- **FR-010**: When a formatting button is tapped with a collapsed cursor (no selection), the system MUST insert opening and closing delimiters at the cursor position and place the cursor between them.
- **FR-011**: When the compose field contains markdown syntax, a read-only live preview MUST appear below the compose field, rendered using `Text(LocalizedStringKey(typingMessage))`.
- **FR-012**: When the compose field contains no markdown syntax, the live preview MUST be hidden.
- **FR-013**: The live preview MUST be styled to resemble a sent message bubble.
- **FR-014**: The byte limit (200 bytes) MUST be enforced on the raw `typingMessage` string using `typingMessage.utf8.count`. The existing `onChange` truncation logic applies unchanged.
- **FR-015**: On send, `typingMessage` (containing raw markdown syntax) MUST be passed directly to `accessoryManager.sendMessage()` with no conversion step.
- **FR-016**: Bold+italic overlap MUST use `***text***` (combined triple-star) syntax.
- **FR-017**: On Mac Catalyst, the existing character palette button MUST remain; formatting buttons MUST also be shown.
- **FR-018**: All formatting buttons MUST use SF Symbols exclusively — no styled text labels, no custom image assets.
- **FR-019**: No UIKit views are permitted — no `UIViewRepresentable`, no `UITextView`, no `NSAttributedString`. All UI MUST be pure SwiftUI.

### Key Entities

- **typingMessage** (`String`): The raw message text including any markdown syntax characters. This is the single source of truth for both the compose field content and the transmitted message. No separate "formatted" or "attributed" representation exists.
- **TextSelection**: The SwiftUI iOS 18 type providing cursor position and selection range within the `TextEditor`. Used to determine where to insert/wrap delimiters and which formatting button states are active.
- **MarkdownStyle**: A logical grouping (Bold, Italic, Strikethrough, Code) each with its opening/closing delimiter strings and corresponding SF Symbol name.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users on iOS 18+ can apply bold, italic, strikethrough, or code formatting to selected text in the compose field within a single tap.
- **SC-002**: Users on iOS 18+ can see a real-time preview of their formatted message before sending, with preview updates appearing as they type.
- **SC-003**: Users on iOS 17.x experience zero changes to their message compose flow — the UI is identical to the pre-feature state.
- **SC-004**: 100% of formatting operations (wrap, unwrap, cursor-insert) complete without exceeding the 200-byte message limit or losing user text.
- **SC-005**: All four formatting styles (bold, italic, strikethrough, code) are accessible within the keyboard toolbar without requiring additional navigation or menus.
- **SC-006**: Formatted messages sent from iOS 18+ users render correctly in the recipient's message bubble on all supported OS versions (recipients do not need iOS 18+ to see rendered markdown).
- **SC-007**: Unit test coverage exists for all markdown wrapping/unwrapping helper functions: wrap with bold/italic/strikethrough/code, unwrap (toggle off), wrap at cursor (empty selection), detect if selection is already wrapped, bold+italic triple-star combination.

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