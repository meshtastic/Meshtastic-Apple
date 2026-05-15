// MARK: MarkdownConverter
//
//  MarkdownConverter.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import Markdown

// MARK: - MarkdownConverter

/// Converts GFM-compatible markdown to HTML using swift-markdown (cmark-gfm).
/// Handles all GFM features: tables, strikethrough, autolinks, task lists.
/// Applies Meshtastic-specific post-processing: callout divs, .md → .html link rewriting,
/// YAML front matter stripping, and Jekyll attribute removal.
enum MarkdownConverter {

	/// Strips YAML front matter (--- ... ---) and Jekyll inline attributes ({: .xxx }).
	static func stripFrontMatter(_ markdown: String) -> String {
		var lines = markdown.components(separatedBy: "\n")
		if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
			lines.removeFirst()
			while let line = lines.first {
				lines.removeFirst()
				if line.trimmingCharacters(in: .whitespaces) == "---" { break }
			}
		}
		lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("{:") }
		return lines.joined(separator: "\n")
	}

	/// Converts markdown string to HTML body content.
	static func convert(_ markdown: String) -> String {
		let cleaned = stripFrontMatter(markdown)
		let document = Document(parsing: cleaned, options: [.parseBlockDirectives, .parseMinimalDoxygen])
		var html = HTMLConverter.convert(document)

		// Post-process: convert blockquote callouts to styled divs
		html = convertCallouts(html)

		// Rewrite .md links to .html
		html = html.replacingOccurrences(
			of: #"href="([^"]*?)\.md""#,
			with: #"href="$1.html""#,
			options: .regularExpression
		)

		return html
	}

	/// Wraps converted HTML body in a full HTML document with CSS link and optional pre-release banner.
	static func wrapInHTMLDocument(
		_ body: String,
		title: String,
		pageId: String,
		languageCode: String,
		cssHref: String = "../assets/docs.css",
		includePreReleaseBanner: Bool = true
	) -> String {
		let banner = includePreReleaseBanner
			? "<div class=\"pre-release-banner\">⚠️ <strong>Pre-release</strong> — subject to change</div>"
			: ""
		return "<!DOCTYPE html>\n<html lang=\"\(languageCode)\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>\(escapeHTML(title))</title>\n  <link rel=\"stylesheet\" href=\"\(cssHref)\">\n</head>\n<body data-page=\"\(pageId)\">\n\(banner)\(body)</body>\n</html>"
	}

	/// Wraps converted HTML body using an absolute file URL to the bundled CSS.
	/// Use this when writing translated HTML to Application Support so CSS resolves correctly.
	static func wrapInHTMLDocumentForFile(
		_ body: String,
		title: String,
		pageId: String,
		languageCode: String
	) -> String {
		// Use absolute bundle URL for CSS so the file loads correctly from any on-disk location
		let cssHref: String
		if let cssURL = Bundle.main.url(forResource: "docs", withExtension: "css", subdirectory: "docs/assets") {
			cssHref = cssURL.absoluteString
		} else {
			cssHref = "../assets/docs.css"
		}
		let hasBanner = body.contains("pre-release-banner")
		let banner = hasBanner ? "" : "<div class=\"pre-release-banner\">⚠️ <strong>Pre-release</strong> — subject to change</div>"
		return "<!DOCTYPE html>\n<html lang=\"\(languageCode)\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>\(escapeHTML(title))</title>\n  <link rel=\"stylesheet\" href=\"\(cssHref)\">\n</head>\n<body data-page=\"\(pageId)\">\n\(banner)\(body)</body>\n</html>"
	}

	/// Re-wraps an already-complete HTML document with an absolute CSS URL.
	/// Used when writing translated HTML to disk so loadFileURL resolves CSS correctly.
	static func rewrapForFile(_ html: String, title: String, pageId: String, languageCode: String) -> String {
		// Extract the body content between <body...> and </body>
		let bodyPattern = try? NSRegularExpression(pattern: #"<body[^>]*>(.*)</body>"#, options: .dotMatchesLineSeparators)
		let body: String
		if let match = bodyPattern?.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
		   let range = Range(match.range(at: 1), in: html) {
			body = String(html[range])
		} else {
			body = html
		}
		// Body already contains the banner from wrapInHTMLDocument — pass through without adding another
		return wrapInHTMLDocumentForFile(body, title: title, pageId: pageId, languageCode: languageCode)
	}

	// MARK: - Callout Conversion

	/// Converts `<blockquote>` elements containing **Tip/Note/Warning** patterns
	/// into styled `<div class="tips-callout">` or `<div class="warning-callout">`.
	private static func convertCallouts(_ html: String) -> String {
		var result = html

		// Tip callouts
		result = result.replacingOccurrences(
			of: #"<blockquote>\s*<p>((?:(?!</p>).)*<strong>(?:(?!</strong>).)*[Tt]ip(?:(?!</strong>).)*</strong>(?:(?!</p>).)*)</p>\s*</blockquote>"#,
			with: #"<div class="tips-callout"><p>$1</p></div>"#,
			options: .regularExpression
		)

		// Note callouts
		result = result.replacingOccurrences(
			of: #"<blockquote>\s*<p>((?:(?!</p>).)*<strong>(?:(?!</strong>).)*[Nn]ote(?:(?!</strong>).)*</strong>(?:(?!</p>).)*)</p>\s*</blockquote>"#,
			with: #"<div class="tips-callout"><p>$1</p></div>"#,
			options: .regularExpression
		)

		// Warning callouts
		result = result.replacingOccurrences(
			of: #"<blockquote>\s*<p>((?:(?!</p>).)*<strong>(?:(?!</strong>).)*[Ww]arning(?:(?!</strong>).)*</strong>(?:(?!</p>).)*)</p>\s*</blockquote>"#,
			with: #"<div class="warning-callout"><p>$1</p></div>"#,
			options: .regularExpression
		)

		// GitHub alert syntax: > [!WARNING], > [!IMPORTANT], > [!NOTE], > [!TIP], > [!CAUTION]
		result = convertGitHubAlerts(result)

		return result
	}

	// MARK: - Inline Processing (for translation segmentation)

	/// Converts GitHub-style alert blockquotes: `> [!WARNING]`, `> [!IMPORTANT]`, etc.
	/// These render as `<blockquote><p>[!TYPE]\nContent</p></blockquote>` after swift-markdown parsing.
	private struct GitHubAlert {
		let pattern: String
		let label: String
		let cssClass: String
		let icon: String
	}

	private static func convertGitHubAlerts(_ html: String) -> String {
		let alertTypes: [GitHubAlert] = [
			GitHubAlert(pattern: "WARNING", label: "Warning", cssClass: "warning-callout", icon: "⚠️"),
			GitHubAlert(pattern: "CAUTION", label: "Caution", cssClass: "warning-callout", icon: "🔴"),
			GitHubAlert(pattern: "IMPORTANT", label: "Important", cssClass: "important-callout", icon: "❗"),
			GitHubAlert(pattern: "NOTE", label: "Note", cssClass: "tips-callout", icon: "ℹ️"),
			GitHubAlert(pattern: "TIP", label: "Tip", cssClass: "tips-callout", icon: "💡"),
		]

		var result = html
		for alert in alertTypes {
			// Match blockquote containing [!TYPE] at the start of the first <p>
			// Use [\s\S] instead of . to match across newlines
			let regex = #"<blockquote>\s*\n?<p>\[!"# + alert.pattern + #"\]\s*"#
				+ #"([\s\S]*?)</blockquote>"#
			result = result.replacingOccurrences(
				of: regex,
				with: "<div class=\"\(alert.cssClass)\"><p><strong>\(alert.icon) \(alert.label)</strong> $1</div>",
				options: .regularExpression
			)
		}
		return result
	}

	// MARK: - Inline Processing (for translation segmentation)

	/// Processes inline markdown: bold, italic, strikethrough, code, links, inline images.
	/// Used by translation segmentation — the main `convert()` uses swift-markdown's full renderer.
	static func processInline(_ text: String) -> String {
		let document = Document(parsing: text)
		return HTMLConverter.convert(document)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Helpers

	static func escapeHTML(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
	}
}

// MARK: - HTMLConverter

/// Walks a swift-markdown Document AST and emits HTML matching cmark-gfm output.
private enum HTMLConverter {

	static func convert(_ document: Document) -> String {
		var visitor = HTMLVisitor()
		return visitor.visitDocument(document)
	}
}

// MARK: - HTMLVisitor

private struct HTMLVisitor: MarkupVisitor {
	typealias Result = String

	mutating func defaultVisit(_ markup: any Markup) -> String {
		markup.children.map { visit($0) }.joined()
	}

	mutating func visitDocument(_ document: Document) -> String {
		document.children.map { visit($0) }.joined()
	}

	mutating func visitHeading(_ heading: Heading) -> String {
		let content = heading.children.map { visit($0) }.joined()
		return "<h\(heading.level)>\(content)</h\(heading.level)>\n"
	}

	mutating func visitParagraph(_ paragraph: Paragraph) -> String {
		let content = paragraph.children.map { visit($0) }.joined()
		return "<p>\(content)</p>\n"
	}

	mutating func visitText(_ text: Text) -> String {
		escapeHTML(text.string)
	}

	mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
		let content = emphasis.children.map { visit($0) }.joined()
		return "<em>\(content)</em>"
	}

	mutating func visitStrong(_ strong: Strong) -> String {
		let content = strong.children.map { visit($0) }.joined()
		return "<strong>\(content)</strong>"
	}

	mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
		let content = strikethrough.children.map { visit($0) }.joined()
		return "<del>\(content)</del>"
	}

	mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
		"<code>\(escapeHTML(inlineCode.code))</code>"
	}

	mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
		let lang = codeBlock.language ?? ""
		let langAttr = lang.isEmpty ? "" : " class=\"language-\(escapeHTML(lang))\""
		return "<pre><code\(langAttr)>\(escapeHTML(codeBlock.code))</code></pre>\n"
	}

	mutating func visitLink(_ link: Link) -> String {
		let content = link.children.map { visit($0) }.joined()
		let dest = link.destination ?? ""
		return "<a href=\"\(dest)\">\(content)</a>"
	}

	mutating func visitImage(_ image: Image) -> String {
		let alt = image.children.map { visit($0) }.joined()
		let src = image.source ?? ""
		return "<img src=\"\(src)\" alt=\"\(alt)\" />"
	}

	mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
		let items = unorderedList.children.map { visit($0) }.joined()
		return "<ul>\n\(items)</ul>\n"
	}

	mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
		let items = orderedList.children.map { visit($0) }.joined()
		return "<ol>\n\(items)</ol>\n"
	}

	mutating func visitListItem(_ listItem: ListItem) -> String {
		let content = listItem.children.map { visit($0) }.joined()
			.trimmingCharacters(in: .whitespacesAndNewlines)
		// For simple single-paragraph list items, unwrap the <p> tags
		if listItem.childCount == 1,
		   content.hasPrefix("<p>") && content.hasSuffix("</p>") {
			let inner = String(content.dropFirst(3).dropLast(4))
			return "<li>\(inner)</li>\n"
		}
		return "<li>\(content)</li>\n"
	}

	mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
		let content = blockQuote.children.map { visit($0) }.joined()
		return "<blockquote>\n\(content)</blockquote>\n"
	}

	mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
		"<hr />\n"
	}

	mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) -> String {
		htmlBlock.rawHTML
	}

	mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
		inlineHTML.rawHTML
	}

	mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
		"\n"
	}

	mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
		"<br />\n"
	}

	mutating func visitTable(_ table: Table) -> String {
		var result = "<table>\n"
		let head = table.head
		result += "<thead>\n<tr>\n"
		for cell in head.cells {
			var cellVisitor = HTMLVisitor()
			let content = cell.children.map { cellVisitor.visit($0) }.joined()
			result += "<th>\(content)</th>\n"
		}
		result += "</tr>\n</thead>\n"

		result += "<tbody>\n"
		for row in table.body.rows {
			result += "<tr>\n"
			for cell in row.cells {
				var cellVisitor = HTMLVisitor()
				let content = cell.children.map { cellVisitor.visit($0) }.joined()
				result += "<td>\(content)</td>\n"
			}
			result += "</tr>\n"
		}
		result += "</tbody>\n</table>\n"
		return result
	}

	// MARK: - Helpers

	private func escapeHTML(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}
}
