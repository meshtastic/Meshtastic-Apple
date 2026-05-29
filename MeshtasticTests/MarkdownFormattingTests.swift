// MARK: MarkdownFormattingTests

import Testing
@testable import Meshtastic

// MARK: - wrapSelection Tests

@Suite("wrapSelection Tests")
struct WrapSelectionTests {

	@Test("Wrap word with bold delimiters")
	func wrapBold() {
		let text = "hello world"
		let range = text.range(of: "world")!
		let result = wrapSelection(in: text, range: range, style: .bold)
		#expect(result.text == "hello **world**")
		#expect(String(result.text[result.selectedRange]) == "**world**")
	}

	@Test("Wrap word with italic delimiters")
	func wrapItalic() {
		let text = "hello world"
		let range = text.range(of: "world")!
		let result = wrapSelection(in: text, range: range, style: .italic)
		#expect(result.text == "hello *world*")
		#expect(String(result.text[result.selectedRange]) == "*world*")
	}

	@Test("Wrap word with strikethrough delimiters")
	func wrapStrikethrough() {
		let text = "hello world"
		let range = text.range(of: "world")!
		let result = wrapSelection(in: text, range: range, style: .strikethrough)
		#expect(result.text == "hello ~~world~~")
		#expect(String(result.text[result.selectedRange]) == "~~world~~")
	}

	@Test("Wrap word with code delimiters")
	func wrapCode() {
		let text = "hello world"
		let range = text.range(of: "world")!
		let result = wrapSelection(in: text, range: range, style: .code)
		#expect(result.text == "hello `world`")
		#expect(String(result.text[result.selectedRange]) == "`world`")
	}

	@Test("Toggle off bold - removes ** delimiters")
	func toggleOffBold() {
		let text = "hello **world**"
		let innerRange = text.range(of: "world")!
		let result = wrapSelection(in: text, range: innerRange, style: .bold)
		#expect(result.text == "hello world")
		#expect(String(result.text[result.selectedRange]) == "world")
	}

	@Test("Toggle off italic - removes * delimiters")
	func toggleOffItalic() {
		let text = "hello *world*"
		let innerRange = text.range(of: "world")!
		let result = wrapSelection(in: text, range: innerRange, style: .italic)
		#expect(result.text == "hello world")
		#expect(String(result.text[result.selectedRange]) == "world")
	}

	@Test("Toggle off strikethrough - removes ~~ delimiters")
	func toggleOffStrikethrough() {
		let text = "hello ~~world~~"
		let innerRange = text.range(of: "world")!
		let result = wrapSelection(in: text, range: innerRange, style: .strikethrough)
		#expect(result.text == "hello world")
		#expect(String(result.text[result.selectedRange]) == "world")
	}

	@Test("Toggle off code - removes backtick delimiters")
	func toggleOffCode() {
		let text = "hello `world`"
		let innerRange = text.range(of: "world")!
		let result = wrapSelection(in: text, range: innerRange, style: .code)
		#expect(result.text == "hello world")
		#expect(String(result.text[result.selectedRange]) == "world")
	}

	@Test("Wrap at start of string")
	func wrapAtStart() {
		let text = "hello world"
		let range = text.range(of: "hello")!
		let result = wrapSelection(in: text, range: range, style: .bold)
		#expect(result.text == "**hello** world")
		#expect(String(result.text[result.selectedRange]) == "**hello**")
	}

	@Test("Wrap entire string")
	func wrapEntireString() {
		let text = "hello"
		let range = text.startIndex..<text.endIndex
		let result = wrapSelection(in: text, range: range, style: .italic)
		#expect(result.text == "*hello*")
		#expect(String(result.text[result.selectedRange]) == "*hello*")
	}

	@Test("Trailing whitespace in selection moves outside delimiters")
	func wrapWithTrailingSpace() {
		let text = "no key or a 1-byte"
		let range = text.range(of: "or ")!
		let result = wrapSelection(in: text, range: range, style: .italic)
		#expect(result.text == "no key *or* a 1-byte")
		#expect(String(result.text[result.selectedRange]) == "*or*")
	}

	@Test("Leading whitespace in selection moves outside delimiters")
	func wrapWithLeadingSpace() {
		let text = "hello world end"
		let range = text.range(of: " world")!
		let result = wrapSelection(in: text, range: range, style: .bold)
		#expect(result.text == "hello **world** end")
		#expect(String(result.text[result.selectedRange]) == "**world**")
	}

	@Test("Leading and trailing whitespace both move outside delimiters")
	func wrapWithSurroundingSpaces() {
		let text = "hello world end"
		let range = text.range(of: " world ")!
		let result = wrapSelection(in: text, range: range, style: .italic)
		#expect(result.text == "hello *world* end")
		#expect(String(result.text[result.selectedRange]) == "*world*")
	}
}

// MARK: - insertDelimiters Tests

@Suite("insertDelimiters Tests")
struct InsertDelimitersTests {

	@Test("Insert bold delimiters at end of string")
	func insertBoldAtEnd() {
		let text = "hello "
		let result = insertDelimiters(in: text, at: text.endIndex, style: .bold)
		#expect(result.text == "hello ****")
		#expect(result.selectedRange.lowerBound == result.selectedRange.upperBound)
		// Cursor should be between the ** pairs
		let cursorOffset = result.text.distance(from: result.text.startIndex, to: result.selectedRange.lowerBound)
		#expect(cursorOffset == 8) // "hello " (6) + "**" (2) = 8
	}

	@Test("Insert italic delimiters at start of empty string")
	func insertItalicInEmpty() {
		let text = ""
		let result = insertDelimiters(in: text, at: text.startIndex, style: .italic)
		#expect(result.text == "**")
		let cursorOffset = result.text.distance(from: result.text.startIndex, to: result.selectedRange.lowerBound)
		#expect(cursorOffset == 1) // After the opening *
	}

	@Test("Insert code delimiters at cursor position")
	func insertCodeAtCursor() {
		let text = "hello world"
		let midIndex = text.index(text.startIndex, offsetBy: 6) // after "hello "
		let result = insertDelimiters(in: text, at: midIndex, style: .code)
		#expect(result.text == "hello ``world")
		let cursorOffset = result.text.distance(from: result.text.startIndex, to: result.selectedRange.lowerBound)
		#expect(cursorOffset == 7) // "hello `" = 7
	}

	@Test("Insert strikethrough delimiters at end")
	func insertStrikethroughAtEnd() {
		let text = "test"
		let result = insertDelimiters(in: text, at: text.endIndex, style: .strikethrough)
		#expect(result.text == "test~~~~")
		let cursorOffset = result.text.distance(from: result.text.startIndex, to: result.selectedRange.lowerBound)
		#expect(cursorOffset == 6) // "test~~" = 6
	}

	@Test("Insert at beginning of non-empty string")
	func insertAtBeginning() {
		let text = "hello"
		let result = insertDelimiters(in: text, at: text.startIndex, style: .bold)
		#expect(result.text == "****hello")
		let cursorOffset = result.text.distance(from: result.text.startIndex, to: result.selectedRange.lowerBound)
		#expect(cursorOffset == 2) // "**" = 2
	}
}

// MARK: - containsMarkdownSyntax Tests

@Suite("containsMarkdownSyntax Tests")
struct ContainsMarkdownSyntaxTests {

	@Test("Plain text returns false")
	func plainText() {
		#expect(!containsMarkdownSyntax("hello world"))
	}

	@Test("Empty string returns false")
	func emptyString() {
		#expect(!containsMarkdownSyntax(""))
	}

	@Test("Paired italic returns true")
	func asterisk() {
		#expect(containsMarkdownSyntax("hello *world*"))
	}

	@Test("Paired bold returns true")
	func doubleAsterisk() {
		#expect(containsMarkdownSyntax("hello **world**"))
	}

	@Test("Paired strikethrough returns true")
	func tilde() {
		#expect(containsMarkdownSyntax("hello ~~world~~"))
	}

	@Test("Paired backtick returns true")
	func backtick() {
		#expect(containsMarkdownSyntax("hello `world`"))
	}

	@Test("Text with only numbers and spaces returns false")
	func numbersAndSpaces() {
		#expect(!containsMarkdownSyntax("123 456 789"))
	}

	@Test("Unpaired delimiters return false")
	func unpairedDelimiters() {
		#expect(!containsMarkdownSyntax("S~~e**e*"))
	}

	@Test("Single asterisk without pair returns false")
	func singleAsterisk() {
		#expect(!containsMarkdownSyntax("hello * world"))
	}

	@Test("Single tilde without pair returns false")
	func singleTilde() {
		#expect(!containsMarkdownSyntax("hello ~ world"))
	}
}

// MARK: - Bold+Italic Combination Tests

@Suite("Bold+Italic Combination Tests")
struct BoldItalicCombinationTests {

	@Test("Apply italic to bold span strips bold and applies italic")
	func boldThenItalic() {
		let text = "hello **world** end"
		let boldSpan = text.range(of: "**world**")!
		let result = wrapSelection(in: text, range: boldSpan, style: .italic)
		#expect(result.text == "hello *world* end")
	}

	@Test("Apply bold to italic span strips italic and applies bold")
	func italicThenBold() {
		let text = "hello *world* end"
		let italicSpan = text.range(of: "*world*")!
		let result = wrapSelection(in: text, range: italicSpan, style: .bold)
		#expect(result.text == "hello **world** end")
	}

	@Test("Apply strikethrough to text with mixed delimiters strips all and applies strikethrough")
	func mixedToStrikethrough() {
		let text = "hello **wo*rld** end"
		let messySpan = text.range(of: "**wo*rld**")!
		let result = wrapSelection(in: text, range: messySpan, style: .strikethrough)
		#expect(result.text == "hello ~~world~~ end")
	}

	@Test("Toggle bold off from triple-star leaves italic")
	func toggleBoldOffFromTripleStar() {
		let text = "hello ***world*** end"
		// Select inner "world" — bold delimiters are **..** immediately around it
		let innerRange = text.range(of: "world")!
		let result = wrapSelection(in: text, range: innerRange, style: .bold)
		#expect(result.text == "hello *world* end")
		#expect(String(result.text[result.selectedRange]) == "world")
	}

	@Test("Garbled delimiters cleaned up on format apply")
	func garbledDelimitersCleanedUp() {
		let text = "abc****~~~****jd~~"
		let range = text.startIndex..<text.endIndex
		let result = wrapSelection(in: text, range: range, style: .bold)
		#expect(result.text == "**abcjd**")
	}

	@Test("Odd count tildes fully stripped")
	func oddTildesStripped() {
		let text = "~~~hello~~~"
		let range = text.startIndex..<text.endIndex
		let result = wrapSelection(in: text, range: range, style: .italic)
		#expect(result.text == "*hello*")
	}

	@Test("Partial selection across delimiter boundary expands to include delimiters")
	func partialDelimiterSelectionExpands() {
		// User selects "he" from "**the** rocky" — selection cuts through closing **
		let text = "**the** rocky"
		// Select "e** " — crossing the delimiter boundary
		let selStart = text.index(text.startIndex, offsetBy: 4) // the 'e'
		let selEnd = text.index(text.startIndex, offsetBy: 8) // space after **
		let range = selStart..<selEnd
		let result = wrapSelection(in: text, range: range, style: .strikethrough)
		// Should expand to include the ** delimiters, strip them, and wrap clean text
		#expect(!result.text.contains("**")) // No orphaned bold delimiters
		#expect(result.text.contains("~~")) // Strikethrough applied
	}

	@Test("Selection starting inside delimiters expands left")
	func selectionStartsInsideDelimiters() {
		let text = "hello **world** end"
		// Select "*world" — starting in the middle of the opening **
		let selStart = text.index(text.startIndex, offsetBy: 7) // second *
		let selEnd = text.index(text.startIndex, offsetBy: 12) // 'd' of world
		let range = selStart..<selEnd
		let result = wrapSelection(in: text, range: range, style: .italic)
		// Should expand to include both ** boundaries
		#expect(!result.text.contains("**"))
	}
}

// MARK: - Link Formatting Tests

@Suite("LinkFormattingTests")
struct LinkFormattingTests {

	@Test("isMarkdownLink returns true for valid link")
	func isMarkdownLinkValid() {
		#expect(isMarkdownLink("[text](https://example.com)"))
	}

	@Test("isMarkdownLink returns false for plain text")
	func isMarkdownLinkPlainText() {
		#expect(!isMarkdownLink("hello world"))
	}

	@Test("isMarkdownLink returns false for partial patterns")
	func isMarkdownLinkPartial() {
		#expect(!isMarkdownLink("[text]"))
		#expect(!isMarkdownLink("(url)"))
		#expect(!isMarkdownLink("[text]("))
	}

	@Test("wrapSelectionWithLink wraps selected text with URL")
	func wrapWithLink() {
		let text = "hello world"
		let range = text.range(of: "hello")!
		let result = wrapSelectionWithLink(in: text, range: range, url: "https://example.com")
		#expect(result.text == "[hello](https://example.com) world")
		#expect(String(result.text[result.selectedRange]) == "[hello](https://example.com)")
	}

	@Test("wrapSelectionWithLink with collapsed cursor inserts placeholder")
	func wrapWithLinkCollapsed() {
		let text = "hello world"
		let cursor = text.index(text.startIndex, offsetBy: 5)
		let range = cursor..<cursor
		let result = wrapSelectionWithLink(in: text, range: range, url: "https://example.com")
		#expect(result.text == "hello[link text](https://example.com) world")
		#expect(String(result.text[result.selectedRange]) == "[link text](https://example.com)")
	}

	@Test("unwrapLink extracts display text from link")
	func unwrapLinkValid() {
		let text = "[hello](https://example.com)"
		let range = text.startIndex..<text.endIndex
		let result = unwrapLink(in: text, range: range)
		#expect(result != nil)
		#expect(result!.text == "hello")
		#expect(String(result!.text[result!.selectedRange]) == "hello")
	}

	@Test("unwrapLink returns nil for plain text")
	func unwrapLinkPlainText() {
		let text = "hello world"
		let range = text.startIndex..<text.endIndex
		let result = unwrapLink(in: text, range: range)
		#expect(result == nil)
	}

	@Test("containsMarkdownSyntax returns true for link syntax")
	func containsMarkdownSyntaxLink() {
		#expect(containsMarkdownSyntax("check [hello](https://example.com) out"))
	}
}
