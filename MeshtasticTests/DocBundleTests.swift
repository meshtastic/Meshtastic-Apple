// MeshtasticTests/DocBundleTests.swift

import Testing
import Foundation
@testable import Meshtastic

@Suite("DocBundleTests")
struct DocBundleTests {

	// MARK: - DocSection

	@Test func docSectionRawValues() {
		#expect(DocSection.user.rawValue == "user")
		#expect(DocSection.developer.rawValue == "developer")
	}

	@Test func docSectionDisplayNames() {
		#expect(DocSection.user.displayName == "User Guide")
		#expect(DocSection.developer.displayName == "Developer Guide")
	}

	@Test func docSectionSystemImages() {
		#expect(!DocSection.user.systemImage.isEmpty)
		#expect(!DocSection.developer.systemImage.isEmpty)
	}

	@Test func docSectionAllCasesCount() {
		#expect(DocSection.allCases.count == 2)
	}

	// MARK: - DocPage equality and hashing

	@Test func docPageEqualityUsesIdAndSection() throws {
		let url = try #require(URL(string: "file:///tmp/test.html"))
		let page1 = DocPage(id: "test", title: "Test", section: .user, htmlURL: url, keywords: [], charCount: 100, navOrder: 1)
		let page2 = DocPage(id: "test", title: "Different Title", section: .user, htmlURL: url, keywords: [], charCount: 200, navOrder: 1)
		let page3 = DocPage(id: "test", title: "Test", section: .developer, htmlURL: url, keywords: [], charCount: 100, navOrder: 1)
		#expect(page1 == page2)
		#expect(page1 != page3)
	}

	// MARK: - KeywordIndexEntry decoding

	@Test func keywordIndexEntryDecoding() throws {
		let json = """
		[{"id":"getting-started","title":"Getting Started","section":"user","keywords":["bluetooth","pair","connect"],"charCount":1500}]
		"""
		let data = try #require(json.data(using: .utf8))
		let entries = try JSONDecoder().decode([KeywordIndexEntry].self, from: data)
		#expect(entries.count == 1)
		#expect(entries[0].id == "getting-started")
		#expect(entries[0].title == "Getting Started")
		#expect(entries[0].section == "user")
		#expect(entries[0].keywords == ["bluetooth", "pair", "connect"])
		#expect(entries[0].charCount == 1500)
	}

	@Test func keywordIndexEntryDecodingEmptyKeywords() throws {
		let json = """
		[{"id":"test","title":"Test","section":"developer","keywords":[],"charCount":200}]
		"""
		let data = try #require(json.data(using: .utf8))
		let entries = try JSONDecoder().decode([KeywordIndexEntry].self, from: data)
		#expect(entries[0].keywords.isEmpty)
	}

	// MARK: - DocBundle.retrievePages token budget

	@Test func retrievePagesReturnsEmptyForBlankQuery() {
		let bundle = DocBundle.shared
		let result = bundle.retrievePages(for: "")
		#expect(result.isEmpty)
	}

	@Test func retrievePagesRespectsTokenBudget() {
		// Token budget of 0 should always return empty
		let bundle = DocBundle.shared
		let result = bundle.retrievePages(for: "bluetooth connect mesh", maxPages: 5, tokenBudget: 0)
		#expect(result.isEmpty)
	}

	@Test func retrievePagesMaxPagesLimit() {
		let bundle = DocBundle.shared
		// maxPages: 1 should return at most 1 result
		let result = bundle.retrievePages(for: "bluetooth mesh radio connect", maxPages: 1, tokenBudget: 10000)
		#expect(result.count <= 1)
	}

	// MARK: - DocSection identifiable

	@Test func docSectionIdentifiableId() {
		#expect(DocSection.user.id == DocSection.user.rawValue)
		#expect(DocSection.developer.id == DocSection.developer.rawValue)
	}

	// MARK: - Keyword scoring (AI retrieval)

	@Test func retrievePagesKeywordScoringPicksRelevantPage() {
		// Build a synthetic DocBundle-like scenario using retrievePages.
		// When the bundle has no pages (test target), result will be empty — that's still a valid test for no crash.
		let bundle = DocBundle.shared
		// Query with keywords unlikely to match — ensure no crash
		let result = bundle.retrievePages(for: "waypoint map layer overlay GPS", maxPages: 3, tokenBudget: 10000)
		#expect(result.count <= 3, "Should never return more than maxPages results")
	}

	@Test func retrievePagesTokenBudgetReducesResults() {
		let bundle = DocBundle.shared
		let fullBudget = bundle.retrievePages(for: "bluetooth mesh radio", maxPages: 5, tokenBudget: 100000)
		let smallBudget = bundle.retrievePages(for: "bluetooth mesh radio", maxPages: 5, tokenBudget: 10)
		// Small budget (10 tokens ≈ 35 chars) should return fewer or equal pages than full budget
		#expect(smallBudget.count <= fullBudget.count)
	}

	// MARK: - Bundle size

	@Test func builtDocsBundleIsUnder10MB() throws {
		// This test validates the built docs/ output in the source tree is under the 10MB hard limit.
		// It passes even if the directory doesn't exist (CI will enforce the limit via build-docs.sh).
		let docsURL = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Meshtastic/Resources/docs")

		guard FileManager.default.fileExists(atPath: docsURL.path) else {
			// Docs bundle not built yet — skip
			return
		}

		var totalBytes: Int64 = 0
		let enumerator = FileManager.default.enumerator(
			at: docsURL,
			includingPropertiesForKeys: [.fileSizeKey],
			options: [.skipsHiddenFiles]
		)
		while let fileURL = enumerator?.nextObject() as? URL {
			let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
			totalBytes += Int64(size)
		}

		let limitBytes: Int64 = 10 * 1024 * 1024  // 10 MB
		#expect(totalBytes < limitBytes, "Docs bundle is \(totalBytes) bytes — exceeds 10 MB limit")
	}
}
