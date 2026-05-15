// MARK: MarkdownConverter
//
//  MarkdownConverter.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation

// MARK: - MarkdownConverter

/// Converts GFM-compatible markdown to HTML matching the output of the `build-docs.sh` pipeline.
/// Supports: headings, paragraphs, lists, code fences, inline code, tables, links, images,
/// HTML passthrough (<picture>, <img>), blockquote callouts (tip/warning), bold, italic,
/// strikethrough, and .md → .html link rewriting.
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
		// Remove Jekyll inline attributes like {: .foo }
		lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("{:") }
		return lines.joined(separator: "\n")
	}

	/// Converts markdown string to HTML body content.
	static func convert(_ markdown: String) -> String {
		let cleaned = stripFrontMatter(markdown)
		let lines = cleaned.components(separatedBy: "\n")
		var html = ""
		var i = 0
		var inCodeBlock = false
		var inTable = false
		var tableHeaderDone = false
		var inBlockquote = false
		var blockquoteLines: [String] = []
		var inList = false

		while i < lines.count {
			let line = lines[i]
			let trimmed = line.trimmingCharacters(in: .whitespaces)

			// Code fences
			if trimmed.hasPrefix("```") {
				if inCodeBlock {
					html += "</code></pre>\n"
					inCodeBlock = false
				} else {
					inCodeBlock = true
					html += "<pre><code>"
				}
				i += 1
				continue
			}

			if inCodeBlock {
				html += escapeHTML(line) + "\n"
				i += 1
				continue
			}

			// Blockquotes
			if trimmed.hasPrefix("> ") || trimmed == ">" {
				if !inBlockquote {
					inBlockquote = true
					blockquoteLines = []
				}
				let content = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
				blockquoteLines.append(content)
				i += 1
				continue
			} else if inBlockquote {
				html += renderBlockquote(blockquoteLines)
				inBlockquote = false
				blockquoteLines = []
				// Don't increment — process this line normally
				continue
			}

			// HTML passthrough (picture, source, img, div)
			if trimmed.hasPrefix("<picture") || trimmed.hasPrefix("<source") || trimmed.hasPrefix("</picture") ||
				trimmed.hasPrefix("<img") || trimmed.hasPrefix("<div") || trimmed.hasPrefix("</div") {
				html += line + "\n"
				i += 1
				continue
			}

			// Table detection
			if trimmed.contains("|") && !trimmed.hasPrefix("```") {
				if isTableSeparator(trimmed) {
					// Header separator row — skip it, header already written
					tableHeaderDone = true
					i += 1
					continue
				}
				if !inTable {
					inTable = true
					tableHeaderDone = false
					html += "<table>\n<thead>\n"
					html += renderTableRow(trimmed, isHeader: true)
					html += "</thead>\n<tbody>\n"
				} else {
					html += renderTableRow(trimmed, isHeader: false)
				}
				i += 1
				continue
			} else if inTable {
				html += "</tbody>\n</table>\n"
				inTable = false
				tableHeaderDone = false
				continue
			}

			// Close list if we're no longer in one
			if inList && !trimmed.hasPrefix("- ") && !trimmed.hasPrefix("* ") && !trimmed.isEmpty {
				html += "</ul>\n"
				inList = false
			}

			// Headings
			if trimmed.hasPrefix("##### ") {
				html += "<h5>\(processInline(String(trimmed.dropFirst(6))))</h5>\n"
			} else if trimmed.hasPrefix("#### ") {
				html += "<h4>\(processInline(String(trimmed.dropFirst(5))))</h4>\n"
			} else if trimmed.hasPrefix("### ") {
				html += "<h3>\(processInline(String(trimmed.dropFirst(4))))</h3>\n"
			} else if trimmed.hasPrefix("## ") {
				html += "<h2>\(processInline(String(trimmed.dropFirst(3))))</h2>\n"
			} else if trimmed.hasPrefix("# ") {
				html += "<h1>\(processInline(String(trimmed.dropFirst(2))))</h1>\n"
			}
			// Images
			else if trimmed.hasPrefix("![") {
				html += renderImage(trimmed)
			}
			// Unordered lists
			else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
				if !inList {
					html += "<ul>\n"
					inList = true
				}
				html += "<li>\(processInline(String(trimmed.dropFirst(2))))</li>\n"
			}
			// Horizontal rule
			else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
				html += "<hr>\n"
			}
			// Empty line
			else if trimmed.isEmpty {
				if inList {
					html += "</ul>\n"
					inList = false
				}
				html += "\n"
			}
			// Paragraph
			else {
				html += "<p>\(processInline(line))</p>\n"
			}

			i += 1
		}

		// Close any open blocks
		if inCodeBlock { html += "</code></pre>\n" }
		if inTable { html += "</tbody>\n</table>\n" }
		if inList { html += "</ul>\n" }
		if inBlockquote { html += renderBlockquote(blockquoteLines) }

		// Rewrite .md links to .html
		html = html.replacingOccurrences(
			of: #"href="([^"]*?)\.md""#,
			with: #"href="$1.html""#,
			options: .regularExpression
		)

		return html
	}

	/// Wraps converted HTML body in a full HTML document with CSS link.
	static func wrapInHTMLDocument(_ body: String, title: String, pageId: String, languageCode: String, cssHref: String = "../assets/docs.css") -> String {
		"""
		<!DOCTYPE html>
		<html lang="\(languageCode)">
		<head>
		  <meta charset="UTF-8">
		  <meta name="viewport" content="width=device-width, initial-scale=1.0">
		  <title>\(title)</title>
		  <link rel="stylesheet" href="\(cssHref)">
		</head>
		<body data-page="\(pageId)">
		\(body)
		</body>
		</html>
		"""
	}

	// MARK: - Inline Formatting

	/// Processes inline markdown: bold, italic, strikethrough, code, links.
	static func processInline(_ text: String) -> String {
		var result = text

		// Inline code (must be first to prevent inner formatting)
		result = result.replacingOccurrences(
			of: #"`([^`]+)`"#,
			with: "<code>$1</code>",
			options: .regularExpression
		)

		// Bold + italic (***text***)
		result = result.replacingOccurrences(
			of: #"\*\*\*(.+?)\*\*\*"#,
			with: "<strong><em>$1</em></strong>",
			options: .regularExpression
		)

		// Bold (**text**)
		result = result.replacingOccurrences(
			of: #"\*\*(.+?)\*\*"#,
			with: "<strong>$1</strong>",
			options: .regularExpression
		)

		// Italic (*text*)
		result = result.replacingOccurrences(
			of: #"\*(.+?)\*"#,
			with: "<em>$1</em>",
			options: .regularExpression
		)

		// Strikethrough (~~text~~)
		result = result.replacingOccurrences(
			of: #"~~(.+?)~~"#,
			with: "<del>$1</del>",
			options: .regularExpression
		)

		// Links [text](url)
		result = result.replacingOccurrences(
			of: #"\[([^\]]+)\]\(([^)]+)\)"#,
			with: #"<a href="$2">$1</a>"#,
			options: .regularExpression
		)

		return result
	}

	// MARK: - Tables

	private static func isTableSeparator(_ line: String) -> Bool {
		let stripped = line.trimmingCharacters(in: .whitespaces)
			.replacingOccurrences(of: "|", with: "")
			.replacingOccurrences(of: "-", with: "")
			.replacingOccurrences(of: ":", with: "")
			.trimmingCharacters(in: .whitespaces)
		return stripped.isEmpty && line.contains("|") && line.contains("-")
	}

	private static func renderTableRow(_ line: String, isHeader: Bool) -> String {
		let cells = line.split(separator: "|", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
		let tag = isHeader ? "th" : "td"
		let cellsHTML = cells.map { "<\(tag)>\(processInline($0))</\(tag)>" }.joined()
		return "<tr>\(cellsHTML)</tr>\n"
	}

	// MARK: - Images

	private static func renderImage(_ line: String) -> String {
		let pattern = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#)
		let range = NSRange(line.startIndex..., in: line)
		if let match = pattern?.firstMatch(in: line, range: range),
		   let altRange = Range(match.range(at: 1), in: line),
		   let srcRange = Range(match.range(at: 2), in: line) {
			let alt = String(line[altRange])
			let src = String(line[srcRange])
			return "<img src=\"\(src)\" alt=\"\(alt)\">\n"
		}
		return "<p>\(processInline(line))</p>\n"
	}

	// MARK: - Blockquotes / Callouts

	private static func renderBlockquote(_ lines: [String]) -> String {
		let content = lines.joined(separator: "\n")
		let processed = processInline(content)

		// Check for tip/warning callout pattern
		if content.range(of: #"\*\*[Tt]ip"#, options: .regularExpression) != nil {
			return "<div class=\"tips-callout\"><p>\(processed)</p></div>\n"
		}
		if content.range(of: #"\*\*[Nn]ote"#, options: .regularExpression) != nil {
			return "<div class=\"tips-callout\"><p>\(processed)</p></div>\n"
		}
		if content.range(of: #"\*\*[Ww]arning"#, options: .regularExpression) != nil {
			return "<div class=\"warning-callout\"><p>\(processed)</p></div>\n"
		}

		return "<blockquote><p>\(processed)</p></blockquote>\n"
	}

	// MARK: - Helpers

	static func escapeHTML(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
	}
}
