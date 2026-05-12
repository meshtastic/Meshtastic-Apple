// MARK: MarkdownFormatting

import Foundation

// MARK: - Types

enum MarkdownStyle: CaseIterable {
	case bold
	case italic
	case strikethrough
	case code
	case link

	var openingDelimiter: String {
		switch self {
		case .bold: return "**"
		case .italic: return "*"
		case .strikethrough: return "~~"
		case .code: return "`"
		case .link: return "["
		}
	}

	var closingDelimiter: String {
		switch self {
		case .link: return "]"
		default: return openingDelimiter
		}
	}

	var sfSymbol: String {
		switch self {
		case .bold: return "bold"
		case .italic: return "italic"
		case .strikethrough: return "strikethrough"
		case .code: return "chevron.left.forwardslash.chevron.right"
		case .link: return "link"
		}
	}
}

struct FormattingResult {
	let text: String
	let selectedRange: Range<String.Index>
}

// MARK: - Functions

/// Wraps the selected substring with markdown delimiters, or removes them if already wrapped (toggle).
func wrapSelection(
	in text: String,
	range: Range<String.Index>,
	style: MarkdownStyle
) -> FormattingResult {
	let opening = style.openingDelimiter
	let closing = style.closingDelimiter

	// First, check toggle-off on the original range (exact delimiter match adjacent to selection)
	let hasOpeningBefore: Bool = {
		let start = range.lowerBound
		guard let checkStart = text.index(start, offsetBy: -opening.count, limitedBy: text.startIndex) else {
			return false
		}
		return String(text[checkStart..<start]) == opening
	}()

	let hasClosingAfter: Bool = {
		let end = range.upperBound
		guard let checkEnd = text.index(end, offsetBy: closing.count, limitedBy: text.endIndex) else {
			return false
		}
		return String(text[end..<checkEnd]) == closing
	}()

	if hasOpeningBefore && hasClosingAfter {
		// Toggle off — remove delimiters
		let delimStart = text.index(range.lowerBound, offsetBy: -opening.count)
		let delimEnd = text.index(range.upperBound, offsetBy: closing.count)

		var newText = text
		newText.removeSubrange(range.upperBound..<delimEnd)
		newText.removeSubrange(delimStart..<range.lowerBound)

		let resultStart = delimStart
		let resultEnd = newText.index(resultStart, offsetBy: text.distance(from: range.lowerBound, to: range.upperBound))
		return FormattingResult(text: newText, selectedRange: resultStart..<resultEnd)
	} else {
		// Expand selection to include any adjacent delimiter characters before wrapping.
		let expandedRange = expandToDelimiterBoundaries(in: text, range: range)

		let selectedText = String(text[expandedRange])
		let cleanedText = stripMarkdownDelimiters(selectedText)

		// Trim whitespace so delimiters hug content
		let trimmed = cleanedText.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else {
			return insertDelimiters(in: text, at: expandedRange.lowerBound, style: style)
		}

		let firstNonWS = cleanedText.firstIndex(where: { !$0.isWhitespace })!
		let leadingWS = String(cleanedText[..<firstNonWS])
		let afterLastNonWS = cleanedText.index(after: cleanedText.lastIndex(where: { !$0.isWhitespace })!)
		let trailingWS = String(cleanedText[afterLastNonWS...])

		let wrapped = leadingWS + opening + trimmed + closing + trailingWS
		var newText = text
		newText.replaceSubrange(expandedRange, with: wrapped)

		// Clean up any orphaned delimiter characters left in the rest of the text
		newText = cleanOrphanedDelimiters(newText)

		// Selection should include the delimiters so the user can see and toggle them
		let fullWrapped = opening + trimmed + closing
		if let fullRange = newText.range(of: fullWrapped) {
			return FormattingResult(text: newText, selectedRange: fullRange)
		}
		let contentStart = newText.index(newText.startIndex, offsetBy: min(leadingWS.count, newText.count))
		let fullLen = opening.count + trimmed.count + closing.count
		let contentEnd = newText.index(contentStart, offsetBy: min(fullLen, newText.distance(from: contentStart, to: newText.endIndex)))
		return FormattingResult(text: newText, selectedRange: contentStart..<contentEnd)
	}
}

/// Inserts opening+closing delimiters at a cursor position and returns cursor between them.
func insertDelimiters(
	in text: String,
	at index: String.Index,
	style: MarkdownStyle
) -> FormattingResult {
	let opening = style.openingDelimiter
	let closing = style.closingDelimiter

	var newText = text
	newText.insert(contentsOf: opening + closing, at: index)

	let cursorPos = newText.index(index, offsetBy: opening.count)
	return FormattingResult(text: newText, selectedRange: cursorPos..<cursorPos)
}

/// Returns true if the given text matches the `[text](url)` markdown link pattern.
func isMarkdownLink(_ text: String) -> Bool {
	text.range(of: "^\\[([^\\]]+)\\]\\(([^)]+)\\)$", options: .regularExpression) != nil
}

/// Wraps selected text with a markdown link `[text](url)`, or inserts a placeholder if the range is collapsed.
func wrapSelectionWithLink(in text: String, range: Range<String.Index>, url: String) -> FormattingResult {
	let selectedText = String(text[range])
	if selectedText.isEmpty {
		// Collapsed cursor — insert placeholder
		let placeholder = "[link text](\(url))"
		var newText = text
		newText.replaceSubrange(range, with: placeholder)
		let start = range.lowerBound
		let end = newText.index(start, offsetBy: placeholder.count)
		return FormattingResult(text: newText, selectedRange: start..<end)
	} else {
		let linkMarkdown = "[\(selectedText)](\(url))"
		var newText = text
		newText.replaceSubrange(range, with: linkMarkdown)
		let start = range.lowerBound
		let end = newText.index(start, offsetBy: linkMarkdown.count)
		return FormattingResult(text: newText, selectedRange: start..<end)
	}
}

/// Unwraps a markdown link `[text](url)` in the selection, returning only the display text.
/// Returns nil if the selected text is not a markdown link.
func unwrapLink(in text: String, range: Range<String.Index>) -> FormattingResult? {
	let selectedText = String(text[range])
	guard let match = selectedText.range(of: "^\\[([^\\]]+)\\]\\(([^)]+)\\)$", options: .regularExpression) else {
		return nil
	}
	// Extract display text between [ and ]
	let inner = selectedText[match]
	guard let openBracket = inner.firstIndex(of: "["),
		  let closeBracket = inner.firstIndex(of: "]") else {
		return nil
	}
	let displayText = String(inner[inner.index(after: openBracket)..<closeBracket])
	var newText = text
	newText.replaceSubrange(range, with: displayText)
	let start = range.lowerBound
	let end = newText.index(start, offsetBy: displayText.count)
	return FormattingResult(text: newText, selectedRange: start..<end)
}

/// Returns true if text contains valid paired markdown formatting syntax.
func containsMarkdownSyntax(_ text: String) -> Bool {
	guard !text.isEmpty else { return false }
	// Check for matched delimiter pairs using regex patterns
	// Bold: **text**
	if text.range(of: "\\*\\*[^*]+\\*\\*", options: .regularExpression) != nil { return true }
	// Italic: *text* (but not **)
	if text.range(of: "(?<!\\*)\\*[^*]+\\*(?!\\*)", options: .regularExpression) != nil { return true }
	// Strikethrough: ~~text~~
	if text.range(of: "~~[^~]+~~", options: .regularExpression) != nil { return true }
	// Code: `text`
	if text.range(of: "`[^`]+`", options: .regularExpression) != nil { return true }
	// Link: [text](url)
	if text.range(of: "\\[[^\\]]+\\]\\([^)]+\\)", options: .regularExpression) != nil { return true }
	return false
}

/// Expands a range to absorb any contiguous markdown delimiter characters (*, ~, `)
/// that touch or are contained within the selection boundaries. This prevents orphaned
/// partial delimiters when the user's selection cuts through existing formatting.
private func expandToDelimiterBoundaries(in text: String, range: Range<String.Index>) -> Range<String.Index> {
	let delimiterChars: Set<Character> = ["*", "~", "`"]
	let selectedText = String(text[range])

	// Only expand if the selection contains delimiter characters or borders them
	let hasDelimitersInside = selectedText.contains(where: { delimiterChars.contains($0) })
	let hasDelimiterBefore = range.lowerBound > text.startIndex && delimiterChars.contains(text[text.index(before: range.lowerBound)])
	let hasDelimiterAfter = range.upperBound < text.endIndex && delimiterChars.contains(text[range.upperBound])

	guard hasDelimitersInside || hasDelimiterBefore || hasDelimiterAfter else {
		return range
	}

	// Expand left: walk backward from lower bound past all delimiter chars
	var lower = range.lowerBound
	while lower > text.startIndex {
		let prev = text.index(before: lower)
		if delimiterChars.contains(text[prev]) {
			lower = prev
		} else {
			break
		}
	}

	// Expand right: walk forward from upper bound past all delimiter chars
	var upper = range.upperBound
	while upper < text.endIndex {
		if delimiterChars.contains(text[upper]) {
			upper = text.index(after: upper)
		} else {
			break
		}
	}

	return lower..<upper
}

/// Strips all markdown delimiter characters from a string, returning plain text.
private func stripMarkdownDelimiters(_ text: String) -> String {
	String(text.filter { $0 != "*" && $0 != "~" && $0 != "`" })
}

/// Removes orphaned (unpaired) delimiter characters from the text.
/// Preserves properly paired delimiters like **bold**, *italic*, ~~strike~~, `code`.
private func cleanOrphanedDelimiters(_ text: String) -> String {
	var result = text

	// Remove orphaned ** (bold) — keep only paired ones
	result = cleanOrphanedPairs(in: result, delimiter: "**")
	// Remove orphaned ~~ (strikethrough)
	result = cleanOrphanedPairs(in: result, delimiter: "~~")
	// Remove orphaned ` (code)
	result = cleanOrphanedPairs(in: result, delimiter: "`")
	// Remove orphaned single * (italic) — must run after ** cleanup
	result = cleanOrphanedPairs(in: result, delimiter: "*")

	return result
}

/// Removes unpaired instances of a delimiter from text.
/// A delimiter is "paired" if it appears an even number of times.
private func cleanOrphanedPairs(in text: String, delimiter: String) -> String {
	// Count occurrences
	var count = 0
	var searchRange = text.startIndex..<text.endIndex
	while let found = text.range(of: delimiter, range: searchRange) {
		count += 1
		searchRange = found.upperBound..<text.endIndex
	}

	// If even count (including 0), all are paired — nothing to clean
	if count % 2 == 0 { return text }

	// Odd count means at least one orphan. Remove the last occurrence.
	guard let lastRange = text.range(of: delimiter, options: .backwards) else { return text }
	var result = text
	result.removeSubrange(lastRange)
	return result
}
