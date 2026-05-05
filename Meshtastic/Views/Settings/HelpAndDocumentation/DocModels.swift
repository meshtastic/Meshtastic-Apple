// MARK: DocModels
//
//  DocModels.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import OSLog

// MARK: - String+HTMLEntityDecoded

private extension String {
	/// Decodes common HTML entities (e.g. &amp; → &, &lt; → <, &gt; → >, &quot; → ", &#39; → ').
	var htmlEntityDecoded: String {
		var result = self
		let entities: [(String, String)] = [
			("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
			("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
			("&nbsp;", "\u{00A0}")
		]
		for (entity, char) in entities {
			result = result.replacingOccurrences(of: entity, with: char)
		}
		return result
	}
}

// MARK: - DocSection

enum DocSection: String, CaseIterable, Identifiable {
	case user
	case developer

	var id: String { rawValue }

	var title: String {
		switch self {
		case .user: return "User Guide"
		case .developer: return "Developer Guide"
		}
	}

	var displayName: String { title }

	var systemImage: String {
		switch self {
		case .user: return "person.fill"
		case .developer: return "chevron.left.forwardslash.chevron.right"
		}
	}
}

// MARK: - KeywordIndexEntry

struct KeywordIndexEntry: Codable {
	let id: String
	let title: String
	let section: String       // "user" or "developer"
	let navOrder: Int?
	let keywords: [String]
	let charCount: Int
}

// MARK: - DocPage

struct DocPage: Identifiable, Hashable {
	let id: String
	let title: String
	let section: DocSection
	let htmlURL: URL
	let keywords: [String]
	let charCount: Int
	let navOrder: Int

	/// SF Symbol name for this page in the table of contents.
	var systemImage: String {
		switch id {
		// User Guide
		case "getting-started":	return "star.fill"
		case "bluetooth":		return "custom.bluetooth"
		case "messages":		return "message.fill"
		case "nodes":			return "antenna.radiowaves.left.and.right"
		case "map":				return "map.fill"
		case "settings":		return "slider.horizontal.3"
		case "telemetry":		return "chart.line.uptrend.xyaxis"
		case "tak":				return "mappin.and.ellipse"
		case "mqtt":			return "network"
		case "discovery":		return "dot.radiowaves.left.and.right"
		case "firmware":		return "arrow.down.circle.fill"
		case "watch":			return "applewatch"
		// Developer Guide
		case "architecture":	return "building.columns.fill"
		case "codebase":		return "chevron.left.forwardslash.chevron.right"
		case "adding-features":	return "plus.square.fill"
		case "transport":		return "wave.3.right"
		case "swiftdata":		return "cylinder.fill"
		case "testing":			return "checkmark.seal.fill"
		case "contributing":	return "person.2.fill"
		default:				return section == .developer
			? "chevron.left.forwardslash.chevron.right"
			: "doc.text.fill"
		}
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
		hasher.combine(section)
	}

	static func == (lhs: DocPage, rhs: DocPage) -> Bool {
		lhs.id == rhs.id && lhs.section == rhs.section
	}
}

// MARK: - DocBundle

@Observable
final class DocBundle {

	static let shared = DocBundle()

	private(set) var pages: [DocPage] = []

	private init() {
		// Lazily populated by load()
	}

	/// Returns all loaded pages.
	func allPages() -> [DocPage] { pages }

	func load() {
		guard let indexURL = Bundle.main.url(
			forResource: "index",
			withExtension: "json",
			subdirectory: "docs"
		) else {
			Logger.docs.warning("docs/index.json not found in main bundle — doc browser will be empty")
			return
		}

		do {
			let data = try Data(contentsOf: indexURL)
			let entries = try JSONDecoder().decode([KeywordIndexEntry].self, from: data)
			pages = entries.compactMap { entry -> DocPage? in
				guard let section = DocSection(rawValue: entry.section) else {
					Logger.docs.warning("Unknown doc section '\(entry.section)' for page '\(entry.id)' — skipping")
					return nil
				}
				guard let htmlURL = Bundle.main.url(
					forResource: entry.id,
					withExtension: "html",
					subdirectory: "docs/\(section.rawValue)"
				) else {
					Logger.docs.warning("HTML file not found in bundle for page '\(entry.id)' in section '\(section.rawValue)' — skipping")
					return nil
				}
				return DocPage(
					id: entry.id,
					title: entry.title.htmlEntityDecoded,
					section: section,
					htmlURL: htmlURL,
					keywords: entry.keywords,
					charCount: entry.charCount,
					navOrder: entry.navOrder ?? 999
				)
			}
			Logger.docs.info("DocBundle loaded \(self.pages.count) pages from index")
		} catch {
			Logger.docs.error("Failed to load docs/index.json: \(error.localizedDescription)")
		}
	}

	/// Returns pages grouped by section, ordered by section order then navOrder.
	func pagesBySection() -> [(section: DocSection, pages: [DocPage])] {
		let grouped = Dictionary(grouping: pages, by: { $0.section })
		return DocSection.allCases.compactMap { section in
			guard let sectionPages = grouped[section], !sectionPages.isEmpty else { return nil }
			return (section: section, pages: sectionPages.sorted { $0.navOrder < $1.navOrder })
		}
	}

	/// Returns the top pages matching the query by keyword count, trimmed to token budget.
	/// - Parameters:
	///   - query: The user's question string.
	///   - maxPages: Maximum number of pages to return (default 3).
	///   - tokenBudget: Approximate token ceiling for combined context (default 3000).
	func retrievePages(for query: String, maxPages: Int = 3, tokenBudget: Int = 3000) -> [DocPage] {
		let terms = query.lowercased()
			.components(separatedBy: .whitespacesAndNewlines)
			.flatMap { $0.components(separatedBy: .punctuationCharacters) }
			.filter { $0.count >= 2 }

		guard !terms.isEmpty else { return [] }

		let scored = pages.map { page -> (page: DocPage, score: Int) in
			let score = page.keywords.filter { kw in terms.contains(where: { $0 == kw || kw.hasPrefix($0) }) }.count
			return (page, score)
		}
		.filter { $0.score > 0 }
		.sorted { $0.score > $1.score }
		.prefix(maxPages)
		.map { $0.page }

		// Trim to token budget using charCount / 3.5 estimate
		var selected: [DocPage] = []
		var estimatedTokens = 0
		for page in scored {
			let pageTokens = Int(Double(page.charCount) / 3.5)
			if estimatedTokens + pageTokens <= tokenBudget {
				selected.append(page)
				estimatedTokens += pageTokens
			} else {
				break
			}
		}
		return selected
	}
}
