# Research: Link Formatting (FR-025 – FR-030)

**Branch**: `004-message-formatting-toolbar` | **Date**: 2026-05-11

## R1: Link Markdown Syntax Handling

**Decision**: Link formatting uses asymmetric delimiters `[text](url)` — unlike the symmetric delimiters used by bold/italic/strikethrough/code. The `MarkdownStyle` enum gains a `.link` case but link wrapping/unwrapping uses dedicated functions rather than the generic `wrapSelection` path.

**Rationale**: The existing `wrapSelection` assumes identical opening/closing delimiters. Link syntax has three distinct parts: `[`, `](`, and `)`, plus a user-provided URL. Forcing this into symmetric delimiters would require awkward hacks and break the delimiter expansion/orphan-cleanup logic.

**Alternatives considered**:
- Extending `wrapSelection` with special-case link logic — rejected because it would bloat an already complex function and the toggle-off detection would not work (link delimiters are not symmetric).
- Using a completely separate formatting pipeline — rejected because we can reuse `FormattingResult` and the `FormattingToolbarButtons` infrastructure.

## R2: SwiftUI Dialog for URL Entry

**Decision**: Use SwiftUI `.alert` with a `TextField` for URL input. This provides a lightweight modal dialog with Confirm/Cancel buttons, keyboard focus on the text field, and dismissal via Cancel or swipe.

**Rationale**: `.alert` with `TextField` is available on iOS 16+ and provides exactly the UX described in FR-025 (dialog with text field + Confirm/Cancel). It's simpler than a `.sheet` and doesn't require custom dismiss logic.

**Alternatives considered**:
- `.sheet` with custom form — rejected as over-engineered for a single text field input.
- `.popover` — rejected because it's unreliable on iPhone (falls back to sheet) and doesn't match the spec's "dialog" language.

## R3: Link Pattern Detection for Toggle-Off (FR-029)

**Decision**: Use a regex pattern `\[([^\]]+)\]\(([^)]+)\)` to detect if the selected text is already a markdown link. If the entire selection matches this pattern, tapping Link removes the link formatting and keeps only the display text.

**Rationale**: This is the simplest reliable way to detect the `[text](url)` pattern. The regex captures both the display text and URL, making extraction trivial.

**Alternatives considered**:
- String prefix/suffix checking — rejected because it doesn't validate the full pattern structure.

## R4: `containsMarkdownSyntax` Update

**Decision**: Add a regex check for `[text](url)` link syntax to `containsMarkdownSyntax()` so the live preview appears when links are present.

**Rationale**: Without this, typing `[hello](https://example.com)` won't show the preview.

## R5: `MarkdownStyle.link` and `allCases` Ordering

**Decision**: Add `.link` to `MarkdownStyle` enum. The `ForEach` in `FormattingToolbarButtons` iterates `allCases`, so `.link` must be the last case to appear after Code and before AlertButton (per FR-030). The `.link` case needs special handling in `applyFormatting` since it triggers a dialog rather than immediate text mutation.

**Rationale**: Keeps the toolbar button generation declarative via `ForEach` while allowing the link button to have distinct behavior.
