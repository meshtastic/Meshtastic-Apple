// MeshtasticTests/MarkdownConverterTests.swift

import Testing
import Foundation
@testable import Meshtastic

@Suite("MarkdownConverterTests")
struct MarkdownConverterTests {

	// MARK: - Front Matter Stripping

	@Test func stripFrontMatterRemovesYAML() {
		let input = """
		---
		title: Test Page
		nav_order: 1
		---

		# Hello
		"""
		let result = MarkdownConverter.stripFrontMatter(input)
		#expect(!result.contains("title: Test Page"))
		#expect(result.contains("# Hello"))
	}

	@Test func stripFrontMatterRemovesJekyllAttributes() {
		let input = """
		# Heading
		{: .no_toc }
		Some text
		"""
		let result = MarkdownConverter.stripFrontMatter(input)
		#expect(!result.contains("{: .no_toc }"))
		#expect(result.contains("# Heading"))
		#expect(result.contains("Some text"))
	}

	@Test func stripFrontMatterPreservesContentWithoutFrontMatter() {
		let input = "# Just a heading\n\nSome text"
		let result = MarkdownConverter.stripFrontMatter(input)
		#expect(result == input)
	}

	// MARK: - Headings

	@Test func convertsH1() {
		let html = MarkdownConverter.convert("# Hello World")
		#expect(html.contains("<h1>Hello World</h1>"))
	}

	@Test func convertsH2() {
		let html = MarkdownConverter.convert("## Section")
		#expect(html.contains("<h2>Section</h2>"))
	}

	@Test func convertsH3() {
		let html = MarkdownConverter.convert("### Subsection")
		#expect(html.contains("<h3>Subsection</h3>"))
	}

	@Test func convertsH4() {
		let html = MarkdownConverter.convert("#### Deep")
		#expect(html.contains("<h4>Deep</h4>"))
	}

	@Test func convertsH5() {
		let html = MarkdownConverter.convert("##### Deeper")
		#expect(html.contains("<h5>Deeper</h5>"))
	}

	// MARK: - Paragraphs

	@Test func convertsParagraph() {
		let html = MarkdownConverter.convert("This is a paragraph.")
		#expect(html.contains("<p>This is a paragraph.</p>"))
	}

	// MARK: - Code Fences

	@Test func convertsCodeFence() {
		let input = """
		```swift
		let x = 42
		```
		"""
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<pre><code") && html.contains("let x = 42"))
		#expect(html.contains("</code></pre>"))
	}

	@Test func codeFenceEscapesHTML() {
		let input = """
		```
		<div>test</div>
		```
		"""
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("&lt;div&gt;"))
	}

	// MARK: - Inline Code

	@Test func convertsInlineCode() {
		let html = MarkdownConverter.convert("Use `print()` for output")
		#expect(html.contains("<code>print()</code>"))
	}

	// MARK: - Bold, Italic, Strikethrough

	@Test func convertsBold() {
		let html = MarkdownConverter.convert("This is **bold** text")
		#expect(html.contains("<strong>bold</strong>"))
	}

	@Test func convertsItalic() {
		let html = MarkdownConverter.convert("This is *italic* text")
		#expect(html.contains("<em>italic</em>"))
	}

	@Test func convertsBoldItalic() {
		let html = MarkdownConverter.convert("This is ***bold italic*** text")
		#expect(html.contains("<em><strong>bold italic</strong></em>"))
	}

	@Test func convertsStrikethrough() {
		let html = MarkdownConverter.convert("This is ~~deleted~~ text")
		#expect(html.contains("<del>deleted</del>"))
	}

	// MARK: - Links

	@Test func convertsLinks() {
		let html = MarkdownConverter.convert("[Meshtastic](https://meshtastic.org)")
		#expect(html.contains(#"<a href="https://meshtastic.org">Meshtastic</a>"#))
	}

	@Test func rewritesMdLinksToHtml() {
		let html = MarkdownConverter.convert("[Settings](settings.md)")
		#expect(html.contains(#"href="settings.html""#))
		#expect(!html.contains(#"href="settings.md""#))
	}

	// MARK: - Images

	@Test func convertsImages() {
		let html = MarkdownConverter.convert("![Alt text](image.png)")
		#expect(html.contains(#"<img src="image.png" alt="Alt text" />"#))
		// Standalone images wrapped in <p> like cmark-gfm
		#expect(html.contains("<p><img"))
	}

	// MARK: - Lists

	@Test func convertsUnorderedListDash() {
		let input = """
		- Item one
		- Item two
		- Item three
		"""
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<ul>"))
		#expect(html.contains("<li>Item one</li>"))
		#expect(html.contains("<li>Item two</li>"))
		#expect(html.contains("<li>Item three</li>"))
		#expect(html.contains("</ul>"))
	}

	@Test func convertsUnorderedListAsterisk() {
		let input = """
		* First
		* Second
		"""
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<li>First</li>"))
		#expect(html.contains("<li>Second</li>"))
	}

	// MARK: - Tables

	@Test func convertsTable() {
		let input = """
		| Name | Value |
		|------|-------|
		| Foo  | 42    |
		| Bar  | 99    |
		"""
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<table>"))
		#expect(html.contains("<thead>"))
		#expect(html.contains("<th>Name</th>"))
		#expect(html.contains("<th>Value</th>"))
		#expect(html.contains("<tbody>"))
		#expect(html.contains("<td>Foo</td>"))
		#expect(html.contains("<td>42</td>"))
		#expect(html.contains("</table>"))
	}

	// MARK: - Horizontal Rules

	@Test func convertsHorizontalRuleDashes() {
		let html = MarkdownConverter.convert("Text\n\n---\n\nMore")
		#expect(html.contains("<hr />"))
	}

	@Test func convertsHorizontalRuleAsterisks() {
		let html = MarkdownConverter.convert("Text\n\n***\n\nMore")
		#expect(html.contains("<hr />"))
	}

	@Test func convertsHorizontalRuleUnderscores() {
		let html = MarkdownConverter.convert("Text\n\n___\n\nMore")
		#expect(html.contains("<hr />"))
	}

	// MARK: - HTML Passthrough

	@Test func passesThroughPictureElement() {
		let input = """
		<picture>
		<source media="(prefers-color-scheme: dark)" srcset="dark.png">
		<img src="light.png" alt="Screenshot">
		</picture>
		"""
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<picture>"))
		#expect(html.contains("<source media="))
		#expect(html.contains(#"<img src="light.png""#))
		#expect(html.contains("</picture>"))
	}

	@Test func passesThroughDivElements() {
		let input = "<div class=\"custom\">Content</div>"
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<div class=\"custom\">Content</div>"))
	}

	// MARK: - Blockquote Callouts

	@Test func convertsTipCallout() {
		let input = "> **Tip — Use this feature wisely**"
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("tips-callout"))
	}

	@Test func convertsWarningCallout() {
		let input = "> **Warning — This is dangerous**"
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("warning-callout"))
	}

	@Test func convertsNoteCallout() {
		let input = "> **Note — Important info**"
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("tips-callout"))
	}

	@Test func convertsPlainBlockquote() {
		let input = "> This is a plain blockquote"
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<blockquote>"))
	}

	// MARK: - Link Rewriting

	@Test func rewritesRelativeMdLinks() {
		let input = "See [architecture](../developer/architecture.md) for details."
		let html = MarkdownConverter.convert(input)
		#expect(html.contains(#"href="../developer/architecture.html""#))
	}

	// MARK: - wrapInHTMLDocument

	@Test func wrapInHTMLDocumentProducesValidHTML() {
		let body = "<h1>Test</h1>"
		let doc = MarkdownConverter.wrapInHTMLDocument(body, title: "Test Page", pageId: "test", languageCode: "fr")
		#expect(doc.contains("<!DOCTYPE html>"))
		#expect(doc.contains(#"lang="fr""#))
		#expect(doc.contains("<title>Test Page</title>"))
		#expect(doc.contains(#"data-page="test""#))
		#expect(doc.contains("<h1>Test</h1>"))
		#expect(doc.contains("docs.css"))
	}

	// MARK: - escapeHTML

	@Test func escapesHTMLEntities() {
		let result = MarkdownConverter.escapeHTML("<script>alert('xss')</script>")
		#expect(result.contains("&lt;script&gt;"))
		#expect(!result.contains("<script>"))
	}

	// MARK: - Ordered Lists

	@Test func convertsOrderedList() {
		let input = """
		1. First item
		2. Second item
		3. Third item
		"""
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<ol>"))
		#expect(html.contains("<li>First item</li>"))
		#expect(html.contains("<li>Second item</li>"))
		#expect(html.contains("<li>Third item</li>"))
		#expect(html.contains("</ol>"))
	}

	// MARK: - Tables with Images

	@Test func convertsTableWithInlineImages() {
		let input = """
		| Icon | Meaning |
		|------|---------|
		| ![lock](lock.png) | Secure channel |
		"""
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<table>"))
		#expect(html.contains(#"<img src="lock.png" alt="lock" />"#))
		#expect(html.contains("Secure channel"))
		#expect(html.contains("</table>"))
	}

	// MARK: - Combined / Integration

	@Test func convertsFullDocumentWithMixedContent() {
		let input = """
		---
		title: Test
		---

		# My Page

		This is a **bold** paragraph with a [link](other.md).

		## Table Section

		| Col A | Col B |
		|-------|-------|
		| 1     | 2     |

		```bash
		echo "hello"
		```

		- Item one
		- Item two

		---

		> **Tip — Remember this**

		Done.
		"""
		let html = MarkdownConverter.convert(input)
		#expect(html.contains("<h1>My Page</h1>"))
		#expect(html.contains("<strong>bold</strong>"))
		#expect(html.contains(#"href="other.html""#))
		#expect(html.contains("<table>"))
		#expect(html.contains("<pre><code"))
		#expect(html.contains("<li>Item one</li>"))
		#expect(html.contains("<hr />"))
		#expect(html.contains("tips-callout"))
		#expect(html.contains("<p>Done.</p>"))
		// Front matter stripped
		#expect(!html.contains("title: Test"))
	}
}
