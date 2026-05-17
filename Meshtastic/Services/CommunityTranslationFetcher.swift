// MARK: CommunityTranslationFetcher
//
//  CommunityTranslationFetcher.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import OSLog

// MARK: - CommunityTranslationFetcher

/// Downloads community-contributed translations from the meshtastic/translations repo
/// before falling back to on-device translation. Available to all users regardless of
/// the "Participate in Distributed Translations" setting.
actor CommunityTranslationFetcher {

	static let shared = CommunityTranslationFetcher()

	private let feedURL = "https://meshtastic.github.io/translations/index.json"
	private let rawBaseURL = "https://raw.githubusercontent.com/meshtastic/translations/master/apple-apps"

	/// Cached feed response — refreshed at most once per app launch.
	private var cachedFeed: TranslationFeed?
	private var feedFetchTask: Task<TranslationFeed?, Never>?
	private var downloadedPages: Set<String> = []

	/// True while buildTranslatedFolder is actively downloading/processing.
	/// Other translation services should check this and wait or skip.
	private(set) var isBuildingFolder = false

	private init() {}

	// MARK: - Feed Model

	struct TranslationFeed: Decodable {
		let generatedAt: String
		let translations: [TranslationSet]
	}

	struct TranslationSet: Decodable {
		let language: String
		let appVersion: String
		let platform: String
		let pageCount: Int
		let generatedAt: String
		let pages: [String]
	}

	// MARK: - Public API

	/// Returns true if a community translation exists for this page and was successfully
	/// downloaded into the local cache.
	func fetchIfAvailable(
		page: DocPage,
		languageCode: String,
		sourceFile: String,
		sourceHash: String
	) async -> Bool {
		let cacheKey = "\(languageCode)/\(sourceFile)"
		guard !downloadedPages.contains(cacheKey) else { return true }

		// Check if community translations exist for this language
		guard let feed = await getFeed(),
			  let translationSet = bestMatch(for: languageCode, in: feed) else {
			return false
		}

		// Check if this specific page is in the set
		let mdFile = "\(page.section.rawValue)/\(page.id).md"
		guard translationSet.pages.contains(mdFile) else { return false }

		// Download the translated markdown
		let remotePath = "\(languageCode)/\(translationSet.appVersion)/\(mdFile)"
		guard let markdown = await downloadFile(remotePath: remotePath) else { return false }

		// Store in the local cache
		await TranslationCache.shared.store(
			translatedMarkdown: markdown,
			sourceFile: sourceFile,
			languageCode: languageCode,
			contentHash: sourceHash
		)

		downloadedPages.insert(cacheKey)
		Logger.docs.info("CommunityTranslationFetcher: Downloaded \(page.id, privacy: .public) [\(languageCode, privacy: .public)] from community translations")
		return true
	}

	/// Bulk-downloads all available community translations for a language into the cache.
	/// Called during prefetch to front-load downloads before on-device translation kicks in.
	func prefetchAll(languageCode: String, pages: [DocPage]) async -> Int {
		guard let feed = await getFeed(),
			  let translationSet = bestMatch(for: languageCode, in: feed) else {
			return 0
		}

		var count = 0
		for page in pages {
			let mdFile = "\(page.section.rawValue)/\(page.id).md"
			let sourceFile = "\(page.section.rawValue)/\(page.id).md"
			let cacheKey = "\(languageCode)/\(sourceFile)"

			guard !downloadedPages.contains(cacheKey),
				  translationSet.pages.contains(mdFile) else { continue }

			// Check if already cached locally
			let sourceURL = page.markdownURL ?? page.htmlURL
			if let sourceHash = TranslationCache.sha256Hash(ofFileAt: sourceURL),
			   await TranslationCache.shared.retrieve(
				sourceFile: sourceFile,
				languageCode: languageCode,
				currentHash: sourceHash
			   ) != nil {
				downloadedPages.insert(cacheKey)
				continue
			}

			let remotePath = "\(languageCode)/\(translationSet.appVersion)/\(mdFile)"
			guard let markdown = await downloadFile(remotePath: remotePath) else { continue }

			if let sourceHash = TranslationCache.sha256Hash(ofFileAt: sourceURL) {
				await TranslationCache.shared.store(
					translatedMarkdown: markdown,
					sourceFile: sourceFile,
					languageCode: languageCode,
					contentHash: sourceHash
				)
			}

			downloadedPages.insert(cacheKey)
			count += 1
		}

		if count > 0 {
			Logger.docs.info("CommunityTranslationFetcher: Downloaded \(count, privacy: .public) pages for \(languageCode, privacy: .public)")
		}

		// Also fetch nav labels and search index
		await fetchNavLabels(languageCode: languageCode, translationSet: translationSet)
		await fetchSearchIndex(languageCode: languageCode, translationSet: translationSet)

		return count
	}

	/// Downloads and imports nav-labels.json for pre-translated page titles.
	func fetchNavLabels(languageCode: String, translationSet: TranslationSet? = nil) async {
		let set: TranslationSet?
		if let provided = translationSet {
			set = provided
		} else if let feed = await getFeed() {
			set = bestMatch(for: languageCode, in: feed)
		} else {
			set = nil
		}
		guard let translationSet = set else { return }

		let remotePath = "\(languageCode)/\(translationSet.appVersion)/nav-labels.json"
		guard let json = await downloadFile(remotePath: remotePath) else { return }
		guard let data = json.data(using: .utf8),
			  let labels = try? JSONDecoder().decode([String: String].self, from: data),
			  !labels.isEmpty else { return }

		await DocTranslationService.shared.importUIStringCache(labels, for: languageCode)
	}

	// MARK: - Build Translated Folder

	/// Downloads all community translations and builds the rendered HTML folder
	/// so DocBundle.load() can use it directly. Returns true if a complete folder was built.
	func buildTranslatedFolder(languageCode: String) async -> Bool {
		// Check if rendered folder already exists
		if await TranslationCache.shared.renderedHTMLRootIfReady(for: languageCode) != nil {
			return true
		}

		isBuildingFolder = true
		defer { isBuildingFolder = false }
		let englishPages = await DocBundle.shared.loadEnglishPages()
		guard !englishPages.isEmpty else { return false }

		guard let feed = await getFeed(),
			  let translationSet = bestMatch(for: languageCode, in: feed) else {
			return false
		}

		// Download all pages and render HTML
		var renderedCount = 0
		for page in englishPages {
			let mdFile = "\(page.section.rawValue)/\(page.id).md"
			guard translationSet.pages.contains(mdFile) else { continue }

			let remotePath = "\(languageCode)/\(translationSet.appVersion)/\(mdFile)"
			guard let markdown = await downloadFile(remotePath: remotePath) else { continue }

			// Store in markdown cache
			let sourceFile = "\(page.section.rawValue)/\(page.id).md"
			let sourceURL = page.markdownURL ?? page.htmlURL
			if let sourceHash = TranslationCache.sha256Hash(ofFileAt: sourceURL) {
				await TranslationCache.shared.store(
					translatedMarkdown: markdown,
					sourceFile: sourceFile,
					languageCode: languageCode,
					contentHash: sourceHash
				)
			}

			// Convert to HTML and write to rendered folder
			let htmlBody = MarkdownConverter.convert(markdown)
			let html = MarkdownConverter.wrapInHTMLDocument(
				htmlBody, title: page.title, pageId: page.id,
				languageCode: languageCode
			)
			await TranslationCache.shared.storeRenderedHTML(html, page: page, languageCode: languageCode)
			renderedCount += 1
		}

		guard renderedCount > 0 else { return false }

		// Download search index and write as rendered index.json
		await fetchSearchIndex(languageCode: languageCode, translationSet: translationSet)
		if let searchEntries = await DocBundle.shared.searchIndex(for: languageCode) {
			await TranslationCache.shared.storeRenderedIndex(searchEntries, languageCode: languageCode)
		} else {
			// Build a basic index from nav labels
			await fetchNavLabels(languageCode: languageCode, translationSet: translationSet)
			let navLabels = await DocTranslationService.shared.exportUIStringCache(for: languageCode)
			var entries: [TranslatedSearchEntry] = []
			for page in englishPages {
				let title = navLabels[page.title] ?? page.title
				entries.append(TranslatedSearchEntry(
					id: page.id,
					section: page.section.rawValue,
					title: title,
					keywords: page.keywords
				))
			}
			await TranslationCache.shared.storeRenderedIndex(entries, languageCode: languageCode)
		}

		Logger.docs.info("CommunityTranslationFetcher: Built translated folder for \(languageCode, privacy: .public) — \(renderedCount, privacy: .public) pages")
		return true
	}

	// MARK: - Search Index

	/// Downloads and imports search-index.json for translated keyword search.
	func fetchSearchIndex(languageCode: String, translationSet: TranslationSet? = nil) async {
		let set: TranslationSet?
		if let provided = translationSet {
			set = provided
		} else if let feed = await getFeed() {
			set = bestMatch(for: languageCode, in: feed)
		} else {
			set = nil
		}
		guard let translationSet = set else { return }

		let remotePath = "\(languageCode)/\(translationSet.appVersion)/search-index.json"
		guard let json = await downloadFile(remotePath: remotePath) else { return }
		guard let data = json.data(using: .utf8),
			  let entries = try? JSONDecoder().decode([TranslatedSearchEntry].self, from: data),
			  !entries.isEmpty else { return }

		await DocBundle.shared.importSearchIndex(entries, for: languageCode)
	}

	// MARK: - Feed (index.json)

	private func getFeed() async -> TranslationFeed? {
		if let cached = cachedFeed { return cached }

		if let existing = feedFetchTask {
			return await existing.value
		}

		let task = Task<TranslationFeed?, Never> {
			guard let url = URL(string: feedURL) else { return nil }
			do {
				let (data, response) = try await URLSession.shared.data(from: url)
				guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
				let feed = try JSONDecoder().decode(TranslationFeed.self, from: data)
				Logger.docs.info("CommunityTranslationFetcher: Feed loaded — \(feed.translations.count, privacy: .public) translation sets available")
				return feed
			} catch {
				Logger.docs.warning("CommunityTranslationFetcher: Failed to fetch feed: \(error.localizedDescription, privacy: .public)")
				return nil
			}
		}

		feedFetchTask = task
		let result = await task.value
		cachedFeed = result
		feedFetchTask = nil
		return result
	}

	/// Find the best matching translation set for a language.
	/// Prefers the current app version; falls back to latest available.
	private func bestMatch(for languageCode: String, in feed: TranslationFeed) -> TranslationSet? {
		let matching = feed.translations.filter { $0.language == languageCode && $0.platform == "apple" }
		guard !matching.isEmpty else { return nil }

		let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

		// Exact version match first
		if let exact = matching.first(where: { $0.appVersion == appVersion }) {
			return exact
		}

		// Fall back to latest available version
		return matching.sorted { $0.appVersion > $1.appVersion }.first
	}

	// MARK: - Download

	private func downloadFile(remotePath: String) async -> String? {
		let urlString = "\(rawBaseURL)/\(remotePath)"
		guard let url = URL(string: urlString) else { return nil }

		do {
			let (data, response) = try await URLSession.shared.data(from: url)
			guard (response as? HTTPURLResponse)?.statusCode == 200,
				  let content = String(data: data, encoding: .utf8),
				  !content.isEmpty else {
				return nil
			}
			return content
		} catch {
			return nil
		}
	}
}
