// MARK: DocTranslationService
//
//  DocTranslationService.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import OSLog
#if !targetEnvironment(macCatalyst)
import Translation
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - TranslationState

enum TranslationState: Equatable {
	case idle
	case loading
	case translated(URL)
	case english
}

// MARK: - DocTranslationService

actor DocTranslationService {

	static let shared = DocTranslationService()

	/// Posted when a language transitions from `supported` to `installed`, signalling that
	/// UI labels which previously failed translation should be retried.
	static let languageBecameAvailableNotification = Foundation.Notification.Name("DocTranslationServiceLanguageBecameAvailable")

	/// Avoids spamming identical availability logs for each translated text segment.
	private var lastAvailabilityStatusByLanguage: [String: String] = [:]
	private var inFlightHTMLByCacheKey: [String: Task<String?, Never>] = [:]
	private var activePrefetchTask: Task<Void, Never>?
	private var uiStringCache: [String: String] = [:]
	private var inFlightUIStringByKey: [String: Task<String, Never>] = [:]
	/// Languages that use FoundationModels first (for register/formality steering).
	/// All other languages use Translation Framework first, with FM as fallback.
	private static let foundationModelsFirstLanguages: Set<String> = ["de"]

	/// Per-language LanguageModelSession cache — typed as `Any?` to avoid
	/// `#if canImport(FoundationModels)` wrapping at the property declaration site.
	private var languageModelSessions: [String: Any] = [:]

	// MARK: - Translation Progress

	/// Tracks overall translation progress for UI display.
	private(set) var translationProgress: TranslationProgress = .idle

	enum TranslationProgress: Equatable {
		case idle
		case translating(completed: Int, total: Int, description: String)
		case finished
	}

	/// Posted whenever `translationProgress` changes so views can observe.
	static let translationProgressDidChange = Foundation.Notification.Name("DocTranslationServiceProgressDidChange")

	private func updateProgress(_ progress: TranslationProgress) {
		translationProgress = progress
		NotificationCenter.default.post(name: Self.translationProgressDidChange, object: nil)
	}

	private init() {}

	/// Clears cached UI string translations so they can be retried.
	func clearUIStringCache() {
		uiStringCache.removeAll()
	}

	/// Exports all cached UI string translations for a given language as a dictionary.
	/// Keys are the source English strings, values are translated strings.
	func exportUIStringCache(for languageCode: String) -> [String: String] {
		let prefix = "\(languageCode)#"
		var result: [String: String] = [:]
		for (key, value) in uiStringCache where key.hasPrefix(prefix) {
			let source = String(key.dropFirst(prefix.count))
			result[source] = value
		}
		return result
	}

	/// Imports pre-translated UI strings into the cache (e.g., from community nav-labels.json).
	func importUIStringCache(_ labels: [String: String], for languageCode: String) {
		for (source, translated) in labels {
			let key = "\(languageCode)#\(source)"
			if uiStringCache[key] == nil {
				uiStringCache[key] = translated
			}
		}
		Logger.docs.info("DocTranslationService: Imported \(labels.count, privacy: .public) nav labels for \(languageCode, privacy: .public)")
	}
	// MARK: - Search Index

	/// Generates a translated search index for all pages by translating titles and extracting
	/// keywords from cached translated markdown. Stores the result in `DocBundle`.
	func generateSearchIndex(for languageCode: String) async {
		let pages = await DocBundle.shared.loadEnglishPages()
		var entries: [TranslatedSearchEntry] = []

		// Pre-translate section names and UI chrome so they end up in the cache / nav-labels
		let chromeStrings = ["Help & Docs", "Search docs"] + DocSection.allCases.map(\.displayName)
		for source in chromeStrings {
			_ = await translatedUIString(source, targetLanguage: languageCode)
		}

		for page in pages {
			let translatedTitle = await translatedUIString(page.title, targetLanguage: languageCode)

			// Extract keywords from cached translated markdown
			var translatedKeywords: [String] = []
			let sourceFile = "\(page.section.rawValue)/\(page.id).md"
			let sourceURL = page.markdownURL ?? page.htmlURL
			if let sourceHash = TranslationCache.sha256Hash(ofFileAt: sourceURL),
			   let cachedURL = await TranslationCache.shared.retrieve(
				sourceFile: sourceFile,
				languageCode: languageCode,
				currentHash: sourceHash
			   ),
			   let content = try? String(contentsOf: cachedURL, encoding: .utf8) {
				translatedKeywords = Self.extractKeywords(from: content)
			}

			// Merge with English keywords so search works in both languages
			let combined = Array(Set(translatedKeywords + page.keywords)).sorted()

			entries.append(TranslatedSearchEntry(
				id: page.id,
				section: page.section.rawValue,
				title: translatedTitle,
				keywords: combined
			))
		}

		await DocBundle.shared.importSearchIndex(entries, for: languageCode)

		// Write rendered index.json so DocBundle can load translated pages on next launch
		await TranslationCache.shared.storeRenderedIndex(entries, languageCode: languageCode)

		Logger.docs.info("DocTranslationService: Generated search index for \(languageCode, privacy: .public) — \(entries.count, privacy: .public) entries")
	}

	/// Exports the current translated search index for a language as JSON data.
	func exportSearchIndex(for languageCode: String) async -> [TranslatedSearchEntry]? {
		await DocBundle.shared.searchIndex(for: languageCode)
	}

	/// Extracts top keywords from translated markdown text (lowercase, 3+ chars, deduped, top 30).
	private static let stopWords: Set<String> = [
		"the", "and", "for", "are", "but", "not", "you", "all", "can", "had",
		"her", "was", "one", "our", "out", "has", "have", "been", "were", "they",
		"this", "that", "with", "will", "each", "make", "from", "them", "than",
		"its", "over", "into", "just", "your", "some", "could", "also", "about",
		"which", "when", "what", "their", "other", "then", "more", "very", "most",
		"como", "para", "por", "con", "una", "los", "las", "del", "que", "est",
		"les", "des", "une", "dans", "pour", "avec", "sur", "qui", "pas", "sont",
		"der", "die", "das", "und", "ein", "den", "dem", "ist", "von", "mit"
	]

	static func extractKeywords(from text: String) -> [String] {
		let words = text.lowercased()
			.components(separatedBy: CharacterSet.alphanumerics.inverted)
			.filter { $0.count >= 3 && !stopWords.contains($0) }

		// Count frequencies, take top 30
		var freq: [String: Int] = [:]
		for word in words { freq[word, default: 0] += 1 }

		return freq.sorted { $0.value > $1.value }
			.prefix(30)
			.map { $0.key }
	}

	// MARK: - Public API

	/// Returns translated HTML string for the given page, or nil if English should be used.
	/// Translates the markdown source, caches the translated `.md`, and converts to HTML.
	func translatedHTMLString(for page: DocPage) async -> String? {
		guard !isEnglish() else { return nil }

		// Don't run on-device translation while community download is building the folder
		if await CommunityTranslationFetcher.shared.isBuildingFolder { return nil }

		let languageCode = currentLanguageCode()

		// Prefer markdown source; fall back to HTML if not bundled
		let useMarkdown = page.markdownURL != nil
		let sourceURL = page.markdownURL ?? page.htmlURL
		let sourceFile = "\(page.section.rawValue)/\(page.id).\(useMarkdown ? "md" : "html")"

		guard let sourceHash = TranslationCache.sha256Hash(ofFileAt: sourceURL) else {
			Logger.docs.warning("DocTranslationService: Cannot hash source for \(page.id, privacy: .public)")
			return nil
		}

		let cacheKey = "\(sourceFile)#\(languageCode)#\(sourceHash)"
		if let task = inFlightHTMLByCacheKey[cacheKey] {
			return await task.value
		}

		let task = Task<String?, Never> {
			// Check cache for translated markdown
			if let cachedURL = await TranslationCache.shared.retrieve(
				sourceFile: sourceFile,
				languageCode: languageCode,
				currentHash: sourceHash
			) {
				Logger.docs.debug("DocTranslationService: Cache hit for \(page.id, privacy: .public) [\(languageCode, privacy: .public)]")
				if let cachedContent = try? String(contentsOf: cachedURL, encoding: .utf8) {
					if useMarkdown {
						let htmlBody = MarkdownConverter.convert(cachedContent)
						return MarkdownConverter.wrapInHTMLDocument(
							htmlBody, title: page.title, pageId: page.id,
							languageCode: languageCode
						)
					}
					return cachedContent
				}
			}

			Logger.docs.info("DocTranslationService: Translating \(page.id, privacy: .public) to \(languageCode, privacy: .public)")

			// Try community translations first (available to all users, no on-device model needed)
			let communityFetched = await CommunityTranslationFetcher.shared.fetchIfAvailable(
				page: page,
				languageCode: languageCode,
				sourceFile: sourceFile,
				sourceHash: sourceHash
			)
			if communityFetched,
			   let cachedURL = await TranslationCache.shared.retrieve(
				sourceFile: sourceFile,
				languageCode: languageCode,
				currentHash: sourceHash
			   ),
			   let cachedContent = try? String(contentsOf: cachedURL, encoding: .utf8) {
				if useMarkdown {
					let htmlBody = MarkdownConverter.convert(cachedContent)
					return MarkdownConverter.wrapInHTMLDocument(
						htmlBody, title: page.title, pageId: page.id,
						languageCode: languageCode
					)
				}
				return cachedContent
			}

			// Fall back to on-device translation

			if useMarkdown {
				// Translate the markdown source
				guard let translatedMd = await self.translateMarkdown(page: page, targetLanguage: languageCode) else {
					Logger.docs.warning("DocTranslationService: Translation failed for \(page.id, privacy: .public) [\(languageCode, privacy: .public)] — falling back to English")
					return nil
				}

				// Cache the translated markdown
				await TranslationCache.shared.store(
					translatedMarkdown: translatedMd,
					sourceFile: sourceFile,
					languageCode: languageCode,
					contentHash: sourceHash
				)

				// Convert to HTML
				let htmlBody = MarkdownConverter.convert(translatedMd)
				return MarkdownConverter.wrapInHTMLDocument(
					htmlBody, title: page.title, pageId: page.id,
					languageCode: languageCode
				)
			} else {
				// Legacy: translate HTML directly
				guard let translatedHTML = await self.translate(page: page, targetLanguage: languageCode) else {
					Logger.docs.warning("DocTranslationService: Translation failed for \(page.id, privacy: .public) [\(languageCode, privacy: .public)] — falling back to English")
					return nil
				}

				await TranslationCache.shared.store(
					translatedMarkdown: translatedHTML,
					sourceFile: sourceFile,
					languageCode: languageCode,
					contentHash: sourceHash
				)

				return translatedHTML
			}
		}

		inFlightHTMLByCacheKey[cacheKey] = task
		var result = await task.value
		inFlightHTMLByCacheKey[cacheKey] = nil

		// Resolve relative image/asset paths to absolute bundle file:// URLs
		// so loadHTMLString can display them (its sandbox doesn't resolve ../ paths)
		if var html = result {
			html = Self.resolveRelativeAssetPaths(in: html, relativeTo: page.htmlURL)
			result = html

			// Write a self-contained HTML file with absolute CSS URL for fast file-based reloads
			await TranslationCache.shared.storeRenderedHTML(
				MarkdownConverter.rewrapForFile(html, title: page.title, pageId: page.id, languageCode: languageCode),
				page: page,
				languageCode: languageCode
			)
		}

		return result
	}

	/// Returns cached translated HTML for a page without triggering translation.
	/// Used by DocPageView to check if a translation is already available.
	func translatedHTMLString(fromCacheOnly page: DocPage) async -> String? {
		guard !isEnglish() else { return nil }

		let languageCode = currentLanguageCode()
		let useMarkdown = page.markdownURL != nil
		let sourceURL = page.markdownURL ?? page.htmlURL
		let sourceFile = "\(page.section.rawValue)/\(page.id).\(useMarkdown ? "md" : "html")"

		guard let sourceHash = TranslationCache.sha256Hash(ofFileAt: sourceURL) else { return nil }

		guard let cachedURL = await TranslationCache.shared.retrieve(
			sourceFile: sourceFile,
			languageCode: languageCode,
			currentHash: sourceHash
		),
		let cachedContent = try? String(contentsOf: cachedURL, encoding: .utf8) else {
			return nil
		}

		var html: String
		if useMarkdown {
			let htmlBody = MarkdownConverter.convert(cachedContent)
			html = MarkdownConverter.wrapInHTMLDocument(
				htmlBody, title: page.title, pageId: page.id,
				languageCode: languageCode
			)
		} else {
			html = cachedContent
		}

		html = Self.resolveRelativeAssetPaths(in: html, relativeTo: page.htmlURL)
		return html
	}

	/// Returns a file URL to translated HTML for the given page, or nil if English should be used.
	/// - Parameter page: The documentation page to translate.
	/// - Returns: A file URL to rendered HTML in the user's language, or nil to use bundled English HTML.
	func translatedHTMLURL(for page: DocPage) async -> URL? {
		// FR-007: Skip if English
		guard !isEnglish() else { return nil }

		let languageCode = currentLanguageCode()
		let sourceFile = "\(page.section.rawValue)/\(page.id).html"

		// Resolve the bundled English source markdown (we hash the HTML source)
		guard let bundledURL = page.htmlURL as URL?,
			  let sourceHash = TranslationCache.sha256Hash(ofFileAt: bundledURL) else {
			Logger.docs.warning("DocTranslationService: Cannot hash source for \(page.id)")
			return nil
		}

		// FR-004: Check cache
		if let cachedMdURL = await TranslationCache.shared.retrieve(
			sourceFile: sourceFile,
			languageCode: languageCode,
			currentHash: sourceHash
		) {
			Logger.docs.debug("DocTranslationService: Cache hit for \(page.id) [\(languageCode)]")
			return wrapMarkdownAsHTML(markdownFileURL: cachedMdURL, page: page)
		}

		// Translate
		Logger.docs.info("DocTranslationService: Translating \(page.id) to \(languageCode)")

		guard let translatedMarkdown = await translate(page: page, targetLanguage: languageCode) else {
			Logger.docs.warning("DocTranslationService: Translation failed for \(page.id) [\(languageCode)] — falling back to English")
			return nil
		}

		// Store in cache
		await TranslationCache.shared.store(
			translatedMarkdown: translatedMarkdown,
			sourceFile: sourceFile,
			languageCode: languageCode,
			contentHash: sourceHash
		)

		// Retrieve stored file URL and wrap as HTML
		if let cachedMdURL = await TranslationCache.shared.retrieve(
			sourceFile: sourceFile,
			languageCode: languageCode,
			currentHash: sourceHash
		) {
			return wrapMarkdownAsHTML(markdownFileURL: cachedMdURL, page: page)
		}

		return nil
	}

	/// Prefetch translations for all pages in background.
	func prefetchAll() async {
		if activePrefetchTask != nil { return }

		// Don't run on-device translation while community download is building the folder
		if await CommunityTranslationFetcher.shared.isBuildingFolder { return }

		let languageCode = currentLanguageCode()
		guard languageCode != "en" else { return }

		let task = Task<Void, Never> {
		// Always use English pages for source material (markdown URLs point to bundle)
		let allPages = await DocBundle.shared.loadEnglishPages()
		// Order: user guide first, then developer guide; within each section by nav_order (front matter)
		let orderedPages: [DocPage] = DocSection.allCases.flatMap { section in
			allPages.filter { $0.section == section }.sorted { $0.navOrder < $1.navOrder }
		}

		let totalPages = orderedPages.count
		let uploadTotal = totalPages + 3 // pages + nav-labels.json + search-index.json + manifest.json
		let participateInDistributedTranslations = UserDefaults.standard.object(forKey: "participateInDistributedTranslations") as? Bool ?? true

		updateProgress(.translating(completed: 0, total: totalPages, description: orderedPages.first?.title ?? "Starting"))

		// Bulk-download community translations first (fast, no on-device model needed)
		let communityCount = await CommunityTranslationFetcher.shared.prefetchAll(
			languageCode: languageCode,
			pages: orderedPages
		)
		if communityCount > 0 {
			Logger.docs.info("DocTranslationService: Pre-loaded \(communityCount, privacy: .public) community translations")
		}

		let minStepDuration: ContinuousClock.Duration = .milliseconds(150)

		// Phase 1: page translations
		for (index, page) in orderedPages.enumerated() {
			let stepStart = ContinuousClock.now
			guard !Task.isCancelled else {
				updateProgress(.idle)
				return
			}
			updateProgress(.translating(completed: index, total: totalPages, description: page.title))
			_ = await translatedHTMLString(for: page)
			_ = await translatedUIString(page.title, targetLanguage: languageCode)
			updateProgress(.translating(completed: index + 1, total: totalPages, description: page.title))
			let elapsed = ContinuousClock.now - stepStart
			if elapsed < minStepDuration {
				try? await Task.sleep(for: minStepDuration - elapsed)
			}
		}

		// Phase 2: nav labels — community fetch + chrome strings (no per-item delay),
		// then per-page with 150 ms minimum so the phase is visible for ~4 s at 27 pages
		if !Task.isCancelled {
			await CommunityTranslationFetcher.shared.fetchNavLabels(languageCode: languageCode)
			await CommunityTranslationFetcher.shared.fetchSearchIndex(languageCode: languageCode)
			let chromeStrings = ["Help & Docs", "Search docs"] + DocSection.allCases.map(\.displayName)
			for source in chromeStrings {
				guard !Task.isCancelled else { break }
				_ = await translatedUIString(source, targetLanguage: languageCode)
			}
		}
		for (index, page) in orderedPages.enumerated() {
			guard !Task.isCancelled else { break }
			let stepStart = ContinuousClock.now
			updateProgress(.translating(completed: index, total: totalPages, description: "Nav Labels"))
			_ = await translatedUIString(page.title, targetLanguage: languageCode)
			updateProgress(.translating(completed: index + 1, total: totalPages, description: "Nav Labels"))
			let elapsed = ContinuousClock.now - stepStart
			if elapsed < minStepDuration {
				try? await Task.sleep(for: minStepDuration - elapsed)
			}
		}

		// Phase 3: search index — per-page with 150 ms minimum
		var searchEntries: [TranslatedSearchEntry] = []
		for (index, page) in orderedPages.enumerated() {
			guard !Task.isCancelled else { break }
			let stepStart = ContinuousClock.now
			updateProgress(.translating(completed: index, total: totalPages, description: "Indexing Page"))
			let translatedTitle = await translatedUIString(page.title, targetLanguage: languageCode)
			var translatedKeywords: [String] = []
			let sourceFile = "\(page.section.rawValue)/\(page.id).md"
			let sourceURL = page.markdownURL ?? page.htmlURL
			if let sourceHash = TranslationCache.sha256Hash(ofFileAt: sourceURL),
			   let cachedURL = await TranslationCache.shared.retrieve(
				sourceFile: sourceFile, languageCode: languageCode, currentHash: sourceHash
			   ),
			   let content = try? String(contentsOf: cachedURL, encoding: .utf8) {
				translatedKeywords = Self.extractKeywords(from: content)
			}
			let combined = Array(Set(translatedKeywords + page.keywords)).sorted()
			searchEntries.append(TranslatedSearchEntry(
				id: page.id, section: page.section.rawValue,
				title: translatedTitle, keywords: combined
			))
			updateProgress(.translating(completed: index + 1, total: totalPages, description: "Indexing Page"))
			let elapsed = ContinuousClock.now - stepStart
			if elapsed < minStepDuration {
				try? await Task.sleep(for: minStepDuration - elapsed)
			}
		}
		if !searchEntries.isEmpty {
			await DocBundle.shared.importSearchIndex(searchEntries, for: languageCode)
			await TranslationCache.shared.storeRenderedIndex(searchEntries, languageCode: languageCode)
			Logger.docs.info("DocTranslationService: Generated search index for \(languageCode, privacy: .public) — \(searchEntries.count, privacy: .public) entries")
		}

		// Auto-upload translations after all pages are cached
		if !Task.isCancelled, participateInDistributedTranslations {
			updateProgress(.translating(completed: 0, total: uploadTotal, description: "Uploading"))
			let result = await DocsTranslationUploader.shared.uploadIfNeeded(
				languageCode: languageCode,
				pages: allPages,
				onProgress: { [self] fileName, completed, total in
					await self.updateProgress(.translating(completed: completed, total: total, description: "Uploading \(fileName)"))
				}
			)
			switch result {
			case .uploaded(let count):
				updateProgress(.translating(completed: uploadTotal, total: uploadTotal, description: "Uploaded \(count) files"))
			case .alreadyExists:
				updateProgress(.translating(completed: uploadTotal, total: uploadTotal, description: "Already shared"))
			case .noToken:
				updateProgress(.translating(completed: uploadTotal, total: uploadTotal, description: "No upload token"))
			}
			let stepStart = ContinuousClock.now
			let elapsed = ContinuousClock.now - stepStart
			if elapsed < minStepDuration {
				try? await Task.sleep(for: minStepDuration - elapsed)
			}
		}

		NotificationCenter.default.post(name: Self.navLabelsDidFinishNotification, object: nil)
		updateProgress(.finished)
		}

		activePrefetchTask = task
		await task.value
		activePrefetchTask = nil
	}

	/// Translate navigation labels and UI chrome strings.
	/// Called after all page translations are complete.
	private func translateNavLabels(languageCode: String, pages: [DocPage]) async {
		// Try to fetch community nav labels and search index first
		await CommunityTranslationFetcher.shared.fetchNavLabels(languageCode: languageCode)
		await CommunityTranslationFetcher.shared.fetchSearchIndex(languageCode: languageCode)

		// Translate all nav chrome strings
		let chromeStrings = ["Help & Docs", "Search docs"] + DocSection.allCases.map(\.displayName)
		for source in chromeStrings {
			guard !Task.isCancelled else { return }
			_ = await translatedUIString(source, targetLanguage: languageCode)
		}

		// Translate all page titles
		for page in pages {
			guard !Task.isCancelled else { return }
			_ = await translatedUIString(page.title, targetLanguage: languageCode)
		}

		Logger.docs.info("DocTranslationService: Nav labels translation complete")
	}

	/// Posted when nav label translations complete so DocBrowserView can refresh.
	static let navLabelsDidFinishNotification = Foundation.Notification.Name("DocTranslationServiceNavLabelsDidFinish")

	#if !targetEnvironment(macCatalyst)
	/// Translate a page using a provided TranslationSession (from .translationTask modifier).
	@available(iOS 26, *)
	func translateWithSession(_ session: TranslationSession, page: DocPage) async -> String? {
		guard let htmlData = try? Data(contentsOf: page.htmlURL),
			  let htmlString = String(data: htmlData, encoding: .utf8) else {
			return nil
		}

		let markdownContent = extractTranslatableContent(from: htmlString)
		let segments = segmentMarkdown(markdownContent)
		var translatedSegments: [String] = []

		do {
			for segment in segments {
				if segment.translatable && !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					let response = try await session.translate(segment.text)
					translatedSegments.append(response.targetText)
				} else {
					translatedSegments.append(segment.text)
				}
			}
			Logger.docs.info("DocTranslationService: Session translated \(translatedSegments.count, privacy: .public) segments for \(page.id, privacy: .public)")
			return translatedSegments.joined()
		} catch {
			Logger.docs.error("DocTranslationService: Session translation error: \(error, privacy: .public)")
			return nil
		}
	}
	#endif

	/// Wrap a cached markdown file URL as HTML for WKWebView display.
	func wrapCachedMarkdown(markdownFileURL: URL, page: DocPage) -> URL? {
		wrapMarkdownAsHTML(markdownFileURL: markdownFileURL, page: page)
	}

	/// Wrap translated markdown string as HTML for WKWebView display.
	func wrapTranslatedMarkdown(_ markdown: String, page: DocPage) -> URL? {
		let htmlBody = markdownToHTML(markdown)
		let docsRoot = page.htmlURL.deletingLastPathComponent().deletingLastPathComponent()
		let cssURL = docsRoot.appendingPathComponent("assets/docs.css")

		let fullHTML = """
		<!DOCTYPE html>
		<html lang="\(currentLanguageCode())">
		<head>
		  <meta charset="UTF-8">
		  <meta name="viewport" content="width=device-width, initial-scale=1.0">
		  <title>\(page.title)</title>
		  <link rel="stylesheet" href="\(cssURL.absoluteString)">
		</head>
		<body data-page="\(page.id)">
		\(htmlBody)
		</body>
		</html>
		"""

		let tempDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("TranslatedDocsHTML", isDirectory: true)
		try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		let outputURL = tempDir.appendingPathComponent("\(page.id)_\(currentLanguageCode()).html")

		do {
			try fullHTML.write(to: outputURL, atomically: true, encoding: .utf8)
			return outputURL
		} catch {
			Logger.docs.error("DocTranslationService: Failed to write translated HTML: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// Returns a cached translation for a UI string if available, without triggering on-device translation.
	func cachedUIString(_ text: String, targetLanguage: String) -> String? {
		let key = "\(targetLanguage)#\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
		return uiStringCache[key]
	}

	/// Translates short UI labels (nav/section/page titles). Falls back to source text.
	func translatedUIString(_ text: String, targetLanguage: String? = nil) async -> String {
		let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !source.isEmpty else { return text }

		let languageCode = targetLanguage ?? currentLanguageCode()
		guard languageCode != "en" else { return text }

		let key = "\(languageCode)#\(source)"
		if let cached = uiStringCache[key] {
			return cached
		}
		if let inFlight = inFlightUIStringByKey[key] {
			return await inFlight.value
		}

		let task = Task<String, Never> {
			if let translated = await self.translateUIText(source, targetLanguage: languageCode),
			   !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				return translated
			}
			return text
		}

		inFlightUIStringByKey[key] = task
		let translated = await task.value
		inFlightUIStringByKey[key] = nil
		uiStringCache[key] = translated
		return translated
	}

	// MARK: - Asset Path Resolution

	/// Resolves relative paths (../assets/...) in HTML to absolute file:// URLs
	/// so that loadHTMLString can display images without file access issues.
	static func resolveRelativeAssetPaths(in html: String, relativeTo pageHTMLURL: URL) -> String {
		let pageDir = pageHTMLURL.deletingLastPathComponent()
		var result = html

		// Resolve src="..." attributes (img tags, source srcset)
		let srcPattern = try? NSRegularExpression(pattern: #"(src|srcset)=\"(\.\./[^\"]+)\""#)
		if let matches = srcPattern?.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
			for match in matches.reversed() {
				guard let attrRange = Range(match.range(at: 1), in: result),
					  let pathRange = Range(match.range(at: 2), in: result),
					  let fullRange = Range(match.range, in: result) else { continue }
				let attr = String(result[attrRange])
				let relativePath = String(result[pathRange])
				let absoluteURL = pageDir.appendingPathComponent(relativePath).standardized
				result.replaceSubrange(fullRange, with: "\(attr)=\"\(absoluteURL.absoluteString)\"")
			}
		}

		// Also resolve href="..." for CSS
		let hrefPattern = try? NSRegularExpression(pattern: #"href=\"(\.\./[^\"]+\.css)\""#)
		if let matches = hrefPattern?.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
			for match in matches.reversed() {
				guard let pathRange = Range(match.range(at: 1), in: result),
					  let fullRange = Range(match.range, in: result) else { continue }
				let relativePath = String(result[pathRange])
				let absoluteURL = pageDir.appendingPathComponent(relativePath).standardized
				result.replaceSubrange(fullRange, with: "href=\"\(absoluteURL.absoluteString)\"")
			}
		}

		return result
	}

	// MARK: - Locale Detection

	private func isEnglish() -> Bool {
		let code = currentLanguageCode()
		return code == "en"
	}

	private func currentLanguageCode() -> String {
		Locale.current.language.languageCode?.identifier ?? "en"
	}

	// MARK: - Translation Engine

	/// Translates a markdown source file, preserving non-translatable segments.
	private func translateMarkdown(page: DocPage, targetLanguage: String) async -> String? {
		guard let mdURL = page.markdownURL,
			  let mdContent = try? String(contentsOf: mdURL, encoding: .utf8) else {
			return nil
		}

		let cleaned = MarkdownConverter.stripFrontMatter(mdContent)
		let segments = segmentMarkdown(cleaned)
		var translatedSegments: [String] = []

		for segment in segments {
			if segment.translatable && !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				// Strip trailing newline before sending to translation engine, then restore it.
				// Translation APIs often strip trailing whitespace, which collapses the blank line
				// before tables and breaks GFM table parsing in swift-markdown.
				let hadTrailingNewline = segment.text.hasSuffix("\n")
				let textToTranslate = hadTrailingNewline ? String(segment.text.dropLast()) : segment.text
				if var translated = await translateText(textToTranslate, targetLanguage: targetLanguage) {
					if segment.isTableCell {
						// Sanitize: pipes and newlines would break table structure
						translated = translated.replacingOccurrences(of: "|", with: "\\|")
						translated = translated.replacingOccurrences(of: "\n", with: " ")
					}
					if hadTrailingNewline && !segment.isTableCell {
						translated += "\n"
					}
					translatedSegments.append(translated)
				} else {
					translatedSegments.append(segment.text) // fallback to English
				}
			} else {
				translatedSegments.append(segment.text)
			}
		}

		return translatedSegments.joined()
	}

	/// Translates a single text string using the best available engine.
	private func translateText(_ text: String, targetLanguage: String) async -> String? {
		if Self.foundationModelsFirstLanguages.contains(targetLanguage) {
			#if canImport(FoundationModels)
			if #available(iOS 26, *),
			   let viaFM = await translateWithFoundationModels(text: text, targetLanguage: targetLanguage) {
				return viaFM
			}
			#endif
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 26, *) {
				return await translateWithTranslationFramework(text: text, targetLanguage: targetLanguage)
			}
			#endif
		} else {
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 26, *),
			   let viaTF = await translateWithTranslationFramework(text: text, targetLanguage: targetLanguage) {
				return viaTF
			}
			#endif
			#if canImport(FoundationModels)
			if #available(iOS 26, *) {
				return await translateWithFoundationModels(text: text, targetLanguage: targetLanguage)
			}
			#endif
		}
		return nil
	}

	private func translateUIText(_ text: String, targetLanguage: String) async -> String? {
		if Self.foundationModelsFirstLanguages.contains(targetLanguage) {
			#if canImport(FoundationModels)
			if #available(iOS 26, *),
			   let viaFM = await translateWithFoundationModels(text: text, targetLanguage: targetLanguage) {
				return viaFM
			}
			#endif
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 26, *) {
				return await translateWithTranslationFramework(text: text, targetLanguage: targetLanguage)
			}
			#endif
		} else {
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 26, *),
			   let viaTF = await translateWithTranslationFramework(text: text, targetLanguage: targetLanguage) {
				return viaTF
			}
			#endif
			#if canImport(FoundationModels)
			if #available(iOS 26, *) {
				return await translateWithFoundationModels(text: text, targetLanguage: targetLanguage)
			}
			#endif
		}
		return nil
	}

	private func translate(page: DocPage, targetLanguage: String) async -> String? {
		guard let htmlData = try? Data(contentsOf: page.htmlURL),
			  let htmlString = String(data: htmlData, encoding: .utf8) else {
			return nil
		}

		return await translateHTMLDocument(htmlString, targetLanguage: targetLanguage)
	}

	/// Translates only text nodes, preserving the original HTML structure and attributes.
	private func translateHTMLDocument(_ html: String, targetLanguage: String) async -> String? {
		let useFoundationModelsFirst = Self.foundationModelsFirstLanguages.contains(targetLanguage)
		var fmSegment: ((String) async -> String?)?
		var tfSegment: ((String) async -> String?)?

		#if canImport(FoundationModels)
		if #available(iOS 26, *) {
			fmSegment = { text in
				await self.translateWithFoundationModels(text: text, targetLanguage: targetLanguage)
			}
		}
		#endif

		#if !targetEnvironment(macCatalyst)
		if #available(iOS 26, *) {
			let source = Locale.Language(identifier: "en")
			let target = Locale.Language(identifier: targetLanguage)
			let availability = LanguageAvailability()
			let status = await availability.status(from: source, to: target)
			let statusDescription = String(describing: status)

			if lastAvailabilityStatusByLanguage[targetLanguage] != statusDescription {
				let previousStatus = lastAvailabilityStatusByLanguage[targetLanguage]
				Logger.docs.info("DocTranslationService: Translation availability for \(targetLanguage, privacy: .public): \(statusDescription, privacy: .public)")
				lastAvailabilityStatusByLanguage[targetLanguage] = statusDescription
				if status == .supported {
					Logger.docs.info("DocTranslationService: Language \(targetLanguage, privacy: .public) supported but not installed — download via Settings > General > Language & Region > Translation Languages")
				}
				// Language pack just finished downloading — notify views to retry UI labels
				if status == .installed && previousStatus != nil {
					Task { @MainActor in
						NotificationCenter.default.post(name: DocTranslationService.languageBecameAvailableNotification, object: nil)
					}
				}
			}

			if status == .installed {
				let session = TranslationSession(installedSource: source, target: target)
				tfSegment = { [self] text in
					do {
						let response = try await session.translate(text)
						return response.targetText
					} catch {
						Logger.docs.error("DocTranslationService: Translation framework error for \(targetLanguage, privacy: .public): \(error, privacy: .public)")
						return nil
					}
				}
			} else if status == .supported {
				// Already logged once via dedup block above
			}
		}
		#endif

		let translateSegment = useFoundationModelsFirst ? (fmSegment ?? tfSegment) : (tfSegment ?? fmSegment)
		guard let translateSegment else { return nil }

		let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>")
		let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
		let matches = tagRegex?.matches(in: html, range: fullRange) ?? []

		var output = ""
		var cursor = html.startIndex
		var protectedTags: [String] = []

		for match in matches {
			guard let tagRange = Range(match.range, in: html) else { continue }

			let textNode = String(html[cursor..<tagRange.lowerBound])
			if protectedTags.isEmpty,
			   !textNode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			   let translated = await translateSegment(textNode) {
				output += escapeHTMLTextNode(translated)
			} else {
				output += textNode
			}

			let tag = String(html[tagRange])
			output += tag
			updateProtectedTagStack(with: tag, stack: &protectedTags)
			cursor = tagRange.upperBound
		}

		let tail = String(html[cursor...])
		if protectedTags.isEmpty,
		   !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
		   let translatedTail = await translateSegment(tail) {
			output += escapeHTMLTextNode(translatedTail)
		} else {
			output += tail
		}

		return output
	}

	private func updateProtectedTagStack(with tag: String, stack: inout [String]) {
		let lower = tag.lowercased()
		let protected = ["script", "style", "code", "pre"]

		if lower.hasPrefix("</") {
			for name in protected where lower.hasPrefix("</\(name)") {
				if let idx = stack.lastIndex(of: name) {
					stack.remove(at: idx)
				}
			}
			return
		}

		if lower.hasPrefix("<!") || lower.hasPrefix("<?") || lower.hasSuffix("/>") {
			return
		}

		for name in protected where lower.hasPrefix("<\(name)") {
			stack.append(name)
		}
	}

	/// Escapes translated text before reinserting into HTML text nodes.
	private func escapeHTMLTextNode(_ text: String) -> String {
		text
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
	}

	#if !targetEnvironment(macCatalyst)
	// MARK: - Translation Framework (iOS 26+)

	@available(iOS 26, *)
	private func translateWithTranslationFramework(text: String, targetLanguage: String) async -> String? {
		do {
			let source = Locale.Language(identifier: "en")
			let target = Locale.Language(identifier: targetLanguage)

			let availability = LanguageAvailability()
			let status = await availability.status(from: source, to: target)
			let statusDescription = String(describing: status)
			if lastAvailabilityStatusByLanguage[targetLanguage] != statusDescription {
				let previousStatus = lastAvailabilityStatusByLanguage[targetLanguage]
				Logger.docs.info("DocTranslationService: Translation availability for \(targetLanguage, privacy: .public): \(statusDescription, privacy: .public)")
				lastAvailabilityStatusByLanguage[targetLanguage] = statusDescription
				if status == .supported {
					Logger.docs.info("DocTranslationService: Language \(targetLanguage, privacy: .public) supported but not installed — download via Settings > General > Language & Region > Translation Languages")
				} else if status != .installed {
					Logger.docs.info("DocTranslationService: Translation framework does not support \(targetLanguage, privacy: .public)")
				}
				if status == .installed && previousStatus != nil {
					Task { @MainActor in
						NotificationCenter.default.post(name: DocTranslationService.languageBecameAvailableNotification, object: nil)
					}
				}
			}

			guard status == .installed else {
				return nil
			}

			let session = TranslationSession(installedSource: source, target: target)
			let response = try await session.translate(text)
			return response.targetText
		} catch {
			Logger.docs.error("DocTranslationService: Translation framework error for \(targetLanguage, privacy: .public): \(error, privacy: .public)")
			return nil
		}
	}
	#endif

	#if canImport(FoundationModels)
	// MARK: - FoundationModels Fallback (iOS 26+)

	@available(iOS 26, *)
	private func translateWithFoundationModels(text: String, targetLanguage: String) async -> String? {
		guard await FoundationModelAvailability.shared.isAvailable else { return nil }

		do {
			let languageName = Locale.current.localizedString(forLanguageCode: targetLanguage) ?? targetLanguage

			let session: LanguageModelSession
			if let cached = languageModelSessions[targetLanguage] as? LanguageModelSession {
				session = cached
			} else {
				let instructions = """
					You are a technical documentation translator. \
					Translate text from English to \(languageName). \
					Always use informal register: in German use du/dich/dir/dein/deine (never Sie/Ihnen/Ihr); \
					in French use tu/toi/ton/ta/tes (never vous/votre); \
					in Spanish use tú/te/tu/tus (never usted/su). \
					Preserve all markdown syntax, code spans, URLs, HTML tags, and special characters exactly. \
					Output only the translated text — no explanations, no preamble.
					"""
				let created = LanguageModelSession(instructions: instructions)
				languageModelSessions[targetLanguage] = created
				session = created
			}

			let response = try await session.respond(to: text)
			return response.content
		} catch {
			await FoundationModelAvailability.shared.reportFailure(error)
			Logger.docs.error("DocTranslationService: FoundationModels error: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}
	#endif

	// MARK: - Markdown Segmentation

	private struct MarkdownSegment {
		let text: String
		let translatable: Bool
		var isTableCell: Bool = false
	}

	/// Splits a line into translatable text and non-translatable inline code spans.
	/// Backtick-wrapped code (`` `code` ``) is preserved verbatim; surrounding text is translatable.
	/// Also preserves callout keyword prefixes like `> **Warning —` untranslated.
	private func segmentInlineCode(_ line: String) -> [MarkdownSegment] {
		var segments: [MarkdownSegment] = []
		let scanner = line[line.startIndex...]
		var current = scanner.startIndex
		var inBacktick = false
		var backtickStart = scanner.startIndex

		var idx = scanner.startIndex
		while idx < scanner.endIndex {
			if scanner[idx] == "`" {
				if inBacktick {
					// End of code span — flush preceding text as translatable, code as non-translatable
					let textBefore = String(scanner[current..<backtickStart])
					if !textBefore.isEmpty {
						segments.append(contentsOf: segmentCalloutPrefix(textBefore))
					}
					let code = String(scanner[backtickStart...idx])
					segments.append(MarkdownSegment(text: code, translatable: false))
					current = scanner.index(after: idx)
					inBacktick = false
				} else {
					inBacktick = true
					backtickStart = idx
				}
			}
			idx = scanner.index(after: idx)
		}

		// Remaining text after last code span
		let remaining = String(scanner[current..<scanner.endIndex])
		if !remaining.isEmpty {
			segments.append(contentsOf: segmentCalloutPrefix(remaining))
		}

		// Append trailing newline
		if let last = segments.last {
			segments[segments.count - 1] = MarkdownSegment(text: last.text + "\n", translatable: last.translatable)
		} else {
			segments.append(MarkdownSegment(text: line + "\n", translatable: true))
		}

		return segments
	}

	/// If text starts with a blockquote callout prefix like `> **Warning — ` or `> **Tip — `,
	/// split the prefix as non-translatable so the keyword isn't translated.
	/// The closing `**` of the title is also protected so translation engines cannot
	/// insert a space before it (which would break bold rendering and callout detection).
	private func segmentCalloutPrefix(_ text: String) -> [MarkdownSegment] {
		// Match patterns like "> **Warning — ", "> **Tip — ", "> **Note — ", "> **Caution — ", "> **Important — "
		let calloutPattern = #"^(>\s*\*\*(?:Warning|Tip|Note|Caution|Important)\s*[-—–]\s*)"#
		guard let regex = try? NSRegularExpression(pattern: calloutPattern),
			  let prefixMatch = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
			  let prefixRange = Range(prefixMatch.range(at: 1), in: text) else {
			return [MarkdownSegment(text: text, translatable: true)]
		}

		let prefix = String(text[prefixRange])           // e.g. "> **Tip — "
		let afterPrefix = String(text[prefixRange.upperBound...])

		// Find the closing ** — protect it so translators cannot add a space before it.
		if let closingRange = afterPrefix.range(of: "**") {
			let title = String(afterPrefix[..<closingRange.lowerBound])    // translatable title text
			let closing = String(afterPrefix[closingRange])                 // "**" — non-translatable
			let body = String(afterPrefix[closingRange.upperBound...])      // optional body text

			var segments: [MarkdownSegment] = [MarkdownSegment(text: prefix, translatable: false)]
			if !title.isEmpty {
				segments.append(MarkdownSegment(text: title, translatable: true))
			}
			segments.append(MarkdownSegment(text: closing, translatable: false))
			if !body.trimmingCharacters(in: .whitespaces).isEmpty {
				segments.append(MarkdownSegment(text: body, translatable: true))
			} else if !body.isEmpty {
				segments.append(MarkdownSegment(text: body, translatable: false))
			}
			return segments
		}

		// No closing ** on this line — preserve prefix, translate the rest.
		var result = [MarkdownSegment(text: prefix, translatable: false)]
		if !afterPrefix.isEmpty {
			result.append(MarkdownSegment(text: afterPrefix, translatable: true))
		}
		return result
	}

	/// Returns true if the line is a GFM table separator (e.g. `|---|---|`).
	private func isTableSeparator(_ trimmed: String) -> Bool {
		trimmed.hasPrefix("|") && trimmed.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
	}

	/// Returns true if the trimmed cell content is an image reference or empty.
	private func isCellNonTranslatable(_ cell: String) -> Bool {
		let t = cell.trimmingCharacters(in: .whitespaces)
		// A cell that is entirely a backtick code span (e.g. `foo.swift`) must not be translated.
		let isCodeSpan = t.count >= 2 && t.hasPrefix("`") && t.hasSuffix("`")
		return t.isEmpty || t.hasPrefix("![") || t.hasPrefix("<img") || isCodeSpan
	}

	/// Splits a markdown table row into segments: pipe delimiters and image cells are
	/// non-translatable; text cells are translatable. The row's trailing newline is preserved.
	private func segmentTableRow(_ line: String) -> [MarkdownSegment] {
		// Split on `|` keeping delimiters as structure
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else {
			// Not a well-formed table row — treat whole line as translatable
			return [MarkdownSegment(text: line + "\n", translatable: true)]
		}

		// Extract cells between pipes (drop leading/trailing empty splits)
		let inner = String(trimmed.dropFirst().dropLast()) // strip outer pipes
		let cells = inner.components(separatedBy: "|")

		var segments: [MarkdownSegment] = []
		segments.append(MarkdownSegment(text: "| ", translatable: false))
		for (index, cell) in cells.enumerated() {
			let cellTrimmed = cell.trimmingCharacters(in: .whitespaces)
			if isCellNonTranslatable(cellTrimmed) {
				segments.append(MarkdownSegment(text: cellTrimmed, translatable: false))
			} else {
				// Split on inline code spans so backtick content is preserved verbatim.
				var inlineSegs = segmentInlineCode(cellTrimmed)
				// segmentInlineCode appends a trailing "\n" — strip it for table cells.
				if !inlineSegs.isEmpty {
					let last = inlineSegs[inlineSegs.count - 1]
					let trimmedText = last.text.hasSuffix("\n") ? String(last.text.dropLast()) : last.text
					inlineSegs[inlineSegs.count - 1] = MarkdownSegment(text: trimmedText, translatable: last.translatable)
				}
				segments.append(contentsOf: inlineSegs.map { seg in
					MarkdownSegment(text: seg.text, translatable: seg.translatable, isTableCell: seg.translatable)
				})
			}
			if index < cells.count - 1 {
				segments.append(MarkdownSegment(text: " | ", translatable: false))
			}
		}
		segments.append(MarkdownSegment(text: " |\n", translatable: false))
		return segments
	}

	/// Splits markdown into translatable and non-translatable segments.
	private func segmentMarkdown(_ text: String) -> [MarkdownSegment] {
		var segments: [MarkdownSegment] = []
		let lines = text.components(separatedBy: "\n")
		var inCodeBlock = false
		var codeBlockAccumulator: [String] = []
		var inHTMLBlock = false
		var htmlBlockAccumulator: [String] = []

		for line in lines {
			let trimmed = line.trimmingCharacters(in: .whitespaces)

			if line.hasPrefix("```") {
				if inCodeBlock {
					codeBlockAccumulator.append(line)
					segments.append(MarkdownSegment(text: codeBlockAccumulator.joined(separator: "\n") + "\n", translatable: false))
					codeBlockAccumulator = []
					inCodeBlock = false
				} else {
					inCodeBlock = true
					codeBlockAccumulator.append(line)
				}
			} else if inCodeBlock {
				codeBlockAccumulator.append(line)
			} else if trimmed.hasPrefix("<picture") {
				inHTMLBlock = true
				htmlBlockAccumulator.append(line)
				if trimmed.contains("</picture>") {
					segments.append(MarkdownSegment(text: htmlBlockAccumulator.joined(separator: "\n") + "\n", translatable: false))
					htmlBlockAccumulator = []
					inHTMLBlock = false
				}
			} else if inHTMLBlock {
				htmlBlockAccumulator.append(line)
				if trimmed.contains("</picture>") {
					segments.append(MarkdownSegment(text: htmlBlockAccumulator.joined(separator: "\n") + "\n", translatable: false))
					htmlBlockAccumulator = []
					inHTMLBlock = false
				}
			} else if trimmed.hasPrefix("![") || trimmed.hasPrefix("<img") {
				// Image lines — do not translate
				segments.append(MarkdownSegment(text: line + "\n", translatable: false))
			} else if trimmed.isEmpty {
				segments.append(MarkdownSegment(text: "\n", translatable: false))
			} else if let headingMatch = trimmed.range(of: #"^(#{1,6})\s+"#, options: .regularExpression) {
				// Heading line — preserve `## ` prefix, translate only the title text
				let prefix = String(trimmed[headingMatch])
				let title = String(trimmed[headingMatch.upperBound...])
				segments.append(MarkdownSegment(text: prefix, translatable: false))
				segments.append(contentsOf: segmentInlineCode(title))
			} else if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
				// Table row — parse per-cell
				if isTableSeparator(trimmed) {
					// Separator row (|---|---|) — never translate
					segments.append(MarkdownSegment(text: line + "\n", translatable: false))
				} else {
					segments.append(contentsOf: segmentTableRow(line))
				}
			} else {
				// Protect inline code spans from translation by splitting them out
				segments.append(contentsOf: segmentInlineCode(line))
			}
		}

		// Handle unclosed blocks
		if !codeBlockAccumulator.isEmpty {
			segments.append(MarkdownSegment(text: codeBlockAccumulator.joined(separator: "\n") + "\n", translatable: false))
		}
		if !htmlBlockAccumulator.isEmpty {
			segments.append(MarkdownSegment(text: htmlBlockAccumulator.joined(separator: "\n") + "\n", translatable: false))
		}

		return segments
	}

	// MARK: - Content Extraction

	/// Simple HTML-to-markdown-like extraction for translation purposes.
	private func extractTranslatableContent(from html: String) -> String {
		var text = html

		// Remove head section
		if let regex = try? NSRegularExpression(pattern: "<head>.*?</head>", options: .dotMatchesLineSeparators) {
			text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
		}

		// Remove script/style tags
		if let regex = try? NSRegularExpression(pattern: "<script[^>]*>.*?</script>", options: .dotMatchesLineSeparators) {
			text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
		}
		if let regex = try? NSRegularExpression(pattern: "<style[^>]*>.*?</style>", options: .dotMatchesLineSeparators) {
			text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
		}

		// Preserve <picture> elements as-is (non-translatable HTML passthrough)
		// Replace with a placeholder that won't be stripped
		var pictureBlocks: [String] = []
		let picturePattern = try? NSRegularExpression(pattern: "<picture[^>]*>.*?</picture>", options: [.dotMatchesLineSeparators])
		if let matches = picturePattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
			for (index, match) in matches.enumerated().reversed() {
				if let range = Range(match.range, in: text) {
					pictureBlocks.insert(String(text[range]), at: 0)
					text.replaceSubrange(range, with: "\n%%PICTURE_\(index)%%\n")
				}
			}
		}

		// Convert <img> tags to markdown image syntax before stripping HTML
		let imgPattern = try? NSRegularExpression(pattern: #"<img\s+[^>]*src="([^"]*)"[^>]*alt="([^"]*)"[^>]*/?\s*>"#, options: [])
		if let imgMatches = imgPattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
			for match in imgMatches.reversed() {
				if let fullRange = Range(match.range, in: text),
				   let srcRange = Range(match.range(at: 1), in: text),
				   let altRange = Range(match.range(at: 2), in: text) {
					let src = String(text[srcRange])
					let alt = String(text[altRange])
					text.replaceSubrange(fullRange, with: "![\(alt)](\(src))")
				}
			}
		}
		// Also handle img with alt before src
		let imgPattern2 = try? NSRegularExpression(pattern: #"<img\s+[^>]*alt="([^"]*)"[^>]*src="([^"]*)"[^>]*/?\s*>"#, options: [])
		if let imgMatches = imgPattern2?.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
			for match in imgMatches.reversed() {
				if let fullRange = Range(match.range, in: text),
				   let altRange = Range(match.range(at: 1), in: text),
				   let srcRange = Range(match.range(at: 2), in: text) {
					let src = String(text[srcRange])
					let alt = String(text[altRange])
					text.replaceSubrange(fullRange, with: "![\(alt)](\(src))")
				}
			}
		}

		// Convert <a> tags to markdown links before stripping HTML
		text = text.replacingOccurrences(
			of: #"<a\s+[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#,
			with: "[$2]($1)",
			options: .regularExpression
		)

		// Convert common HTML to markdown approximations
		text = text.replacingOccurrences(of: "<h1[^>]*>", with: "# ", options: .regularExpression)
		text = text.replacingOccurrences(of: "<h2[^>]*>", with: "## ", options: .regularExpression)
		text = text.replacingOccurrences(of: "<h3[^>]*>", with: "### ", options: .regularExpression)
		text = text.replacingOccurrences(of: "<h4[^>]*>", with: "#### ", options: .regularExpression)
		text = text.replacingOccurrences(of: "</h[1-4]>", with: "\n", options: .regularExpression)
		text = text.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
		text = text.replacingOccurrences(of: "</p>", with: "\n\n")
		text = text.replacingOccurrences(of: "<br[^>]*/?>", with: "\n", options: .regularExpression)
		text = text.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)
		text = text.replacingOccurrences(of: "</li>", with: "\n")
		text = text.replacingOccurrences(of: "<strong>", with: "**")
		text = text.replacingOccurrences(of: "</strong>", with: "**")
		text = text.replacingOccurrences(of: "<em>", with: "*")
		text = text.replacingOccurrences(of: "</em>", with: "*")
		text = text.replacingOccurrences(of: "<code>", with: "`")
		text = text.replacingOccurrences(of: "</code>", with: "`")

		// Remove remaining HTML tags (but NOT picture placeholders)
		text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

		// Restore picture blocks
		for (index, block) in pictureBlocks.enumerated() {
			text = text.replacingOccurrences(of: "%%PICTURE_\(index)%%", with: block)
		}

		// Decode HTML entities
		text = text.replacingOccurrences(of: "&amp;", with: "&")
		text = text.replacingOccurrences(of: "&lt;", with: "<")
		text = text.replacingOccurrences(of: "&gt;", with: ">")
		text = text.replacingOccurrences(of: "&quot;", with: "\"")
		text = text.replacingOccurrences(of: "&#39;", with: "'")
		text = text.replacingOccurrences(of: "&nbsp;", with: " ")

		// Clean up multiple blank lines
		while text.contains("\n\n\n") {
			text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
		}

		return text.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - HTML Wrapping

	// MARK: - HTML Generation

	/// Builds a complete HTML string from translated markdown, using relative CSS path.
	private func buildHTMLString(markdownBody: String, page: DocPage) -> String {
		let htmlBody = markdownToHTML(markdownBody)
		return """
		<!DOCTYPE html>
		<html lang="\(currentLanguageCode())">
		<head>
		  <meta charset="UTF-8">
		  <meta name="viewport" content="width=device-width, initial-scale=1.0">
		  <title>\(page.title)</title>
		  <link rel="stylesheet" href="assets/docs.css">
		</head>
		<body data-page="\(page.id)">
		\(htmlBody)
		</body>
		</html>
		"""
	}

	/// Wraps a translated markdown file in the same HTML shell as bundled docs.
	private func wrapMarkdownAsHTML(markdownFileURL: URL, page: DocPage) -> URL? {
		guard let markdownContent = try? String(contentsOf: markdownFileURL, encoding: .utf8) else {
			return nil
		}

		// Convert markdown to basic HTML
		let htmlBody = markdownToHTML(markdownContent)

		// Get the CSS path relative to the docs root
		let docsRoot = page.htmlURL.deletingLastPathComponent().deletingLastPathComponent()
		let cssURL = docsRoot.appendingPathComponent("assets/docs.css")

		let fullHTML = """
		<!DOCTYPE html>
		<html lang="\(currentLanguageCode())">
		<head>
		  <meta charset="UTF-8">
		  <meta name="viewport" content="width=device-width, initial-scale=1.0">
		  <title>\(page.title)</title>
		  <link rel="stylesheet" href="\(cssURL.absoluteString)">
		</head>
		<body data-page="\(page.id)">
		\(htmlBody)
		</body>
		</html>
		"""

		// Write to a temp file that WKWebView can load
		let tempDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("TranslatedDocsHTML", isDirectory: true)
		try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
		let outputURL = tempDir.appendingPathComponent("\(page.id)_\(currentLanguageCode()).html")

		do {
			try fullHTML.write(to: outputURL, atomically: true, encoding: .utf8)
			return outputURL
		} catch {
			Logger.docs.error("DocTranslationService: Failed to write translated HTML: \(error.localizedDescription)")
			return nil
		}
	}

	/// Simple markdown-to-HTML conversion for translated content.
	private func markdownToHTML(_ markdown: String) -> String {
		var html = ""
		let lines = markdown.components(separatedBy: "\n")
		var inCodeBlock = false

		for line in lines {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if line.hasPrefix("```") {
				if inCodeBlock {
					html += "</code></pre>\n"
					inCodeBlock = false
				} else {
					inCodeBlock = true
					html += "<pre><code>"
				}
			} else if inCodeBlock {
				html += escapeHTML(line) + "\n"
			} else if trimmed.hasPrefix("<picture") || trimmed.hasPrefix("<source") || trimmed.hasPrefix("</picture") || trimmed.hasPrefix("<img") {
				// Pass through HTML blocks (picture elements, img tags) unchanged
				html += line + "\n"
			} else if trimmed.hasPrefix("![") {
				// Convert markdown image to HTML img
				let imgPattern = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#)
				if let match = imgPattern?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
				   let altRange = Range(match.range(at: 1), in: trimmed),
				   let srcRange = Range(match.range(at: 2), in: trimmed) {
					let alt = String(trimmed[altRange])
					let src = String(trimmed[srcRange])
					html += "<img src=\"\(src)\" alt=\"\(alt)\">\n"
				} else {
					html += "<p>\(line)</p>\n"
				}
			} else if line.hasPrefix("#### ") {
				html += "<h4>\(String(line.dropFirst(5)))</h4>\n"
			} else if line.hasPrefix("### ") {
				html += "<h3>\(String(line.dropFirst(4)))</h3>\n"
			} else if line.hasPrefix("## ") {
				html += "<h2>\(String(line.dropFirst(3)))</h2>\n"
			} else if line.hasPrefix("# ") {
				html += "<h1>\(String(line.dropFirst(2)))</h1>\n"
			} else if line.hasPrefix("- ") {
				html += "<li>\(String(line.dropFirst(2)))</li>\n"
			} else if trimmed.isEmpty {
				html += "\n"
			} else {
				html += "<p>\(line)</p>\n"
			}
		}

		if inCodeBlock {
			html += "</code></pre>\n"
		}

		return html
	}

	private func escapeHTML(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
	}
}
