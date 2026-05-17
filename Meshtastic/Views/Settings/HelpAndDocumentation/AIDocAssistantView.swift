// WMeshtastic/Views/Settings/HelpAndDocumentation/AIDocAssistantView.swift

import SwiftUI
import OSLog
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Message model

private struct ChirpyMessage: Identifiable {
	let id = UUID()
	let isUser: Bool
	let text: String
	/// Local doc pages used to generate this reply. Empty for user messages.
	let sourcePages: [DocPage]
	/// Explicit meshtastic.org links found in the reply markdown.
	let sourceWebLinks: [ChirpyWebLink]

	init(isUser: Bool, text: String, sourcePages: [DocPage] = [], sourceWebLinks: [ChirpyWebLink] = []) {
		self.isUser = isUser
		self.text = text
		self.sourcePages = sourcePages
		self.sourceWebLinks = sourceWebLinks
	}
}

private struct ChirpyWebLink: Identifiable, Hashable {
	let title: String
	let url: URL

	var id: String {
		"\(title)|\(url.absoluteString)"
	}
}

private struct ChirpyWebSnippet: Hashable {
	let title: String
	let url: URL
	let content: String
}

// MARK: - AIDocAssistantView (iOS 26+ only)

@available(iOS 26, *)
struct AIDocAssistantView: View {

	@Environment(\.dismiss) private var dismiss

	@State private var query = ""
	@State private var messages: [ChirpyMessage] = []
	@State private var isLoading = false
	@State private var errorMessage: String?
	@FocusState private var isInputFocused: Bool
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	private let bundle = DocBundle.shared
	private let groundingScoreThreshold = 1

	// MARK: Body

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				ScrollViewReader { proxy in
					ScrollView {
						LazyVStack(spacing: 0) {
							if messages.isEmpty {
								welcomeCard
									.padding(.top, 40)
									.padding(.bottom, 16)
							}
							ForEach(messages) { message in
								messageBubble(message)
									.padding(.horizontal, 12)
									.padding(.vertical, 3)
							}
							if isLoading {
								thinkingBubble
									.padding(.horizontal, 12)
									.padding(.vertical, 3)
							}
							if let error = errorMessage {
								errorBanner(error)
									.padding(.horizontal, 12)
									.padding(.vertical, 3)
							}
							Color.clear.frame(height: 4).id("bottom")
						}
						.padding(.bottom, 4)
					}
					.scrollDismissesKeyboard(.interactively)
					.onChange(of: messages.count) { _, _ in
						withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
					}
					.onChange(of: isLoading) { _, newValue in
						if newValue {
							withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
						}
					}
				}

				Divider()
				inputBar
			}
			.navigationTitle("Ask Chirpy")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
	}

	// MARK: Welcome card

	// SVG viewBox is 1871.69 × 2607.94 — portrait ratio ~0.718 w:h
	private let chirpyAspect: CGFloat = 1871.69 / 2607.94

	private var chirpyAvatarSize: CGFloat {
		#if targetEnvironment(macCatalyst)
		112
		#else
		horizontalSizeClass == .compact ? 56 : 28
		#endif
	}

	private var sourceLinkFont: Font {
		#if targetEnvironment(macCatalyst)
		.system(size: 18)
		#else
		.caption
		#endif
	}

	private var sourceLinkIconFont: Font {
		#if targetEnvironment(macCatalyst)
		.system(size: 16, weight: .semibold)
		#else
		.caption
		#endif
	}

	private var sourceLinkSpacing: CGFloat {
		#if targetEnvironment(macCatalyst)
		7
		#else
		4
		#endif
	}

	private var welcomeCard: some View {
		VStack(spacing: 16) {
			Image("Chirpy")
				.resizable()
				.scaledToFit()
				.frame(width: 120 * chirpyAspect, height: 120)
				.shadow(color: .black.opacity(0.10), radius: 8, y: 4)
				.accessibilityHidden(true)
			Text("Hi, I'm Chirpy!")
				.font(.title2.bold())
			Text("Ask me anything about Meshtastic.\nI'll search the docs and answer in plain language.")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.padding(.horizontal, 32)
		.frame(maxWidth: .infinity)
	}

	// MARK: Message bubbles

	@ViewBuilder
	private func messageBubble(_ message: ChirpyMessage) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(alignment: .bottom, spacing: 8) {
				if message.isUser {
					Spacer(minLength: 56)
					Text(message.text)
						.padding(.horizontal, 14)
						.padding(.vertical, 10)
						.background(Color.accentColor)
						.foregroundStyle(.white)
						.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
						.textSelection(.enabled)
				} else {
					chirpyAvatarSmall
					Text(markdownAttributedString(message.text))
						.padding(.horizontal, 14)
						.padding(.vertical, 10)
						.background(Color(uiColor: .secondarySystemBackground))
						.foregroundStyle(.primary)
						.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
						.textSelection(.enabled)
					Spacer(minLength: 56)
				}
			}
			if !message.isUser && (!message.sourcePages.isEmpty || !message.sourceWebLinks.isEmpty) {
				// Indent to align with the bubble (avatar width + spacing)
				let avatarWidth = chirpyAvatarSize * chirpyAspect + 8
				VStack(alignment: .leading, spacing: sourceLinkSpacing) {
					ForEach(message.sourcePages) { page in
						NavigationLink(destination: DocPageView(page: page)) {
							HStack(spacing: 6) {
								Image(systemName: "doc.text")
									.font(sourceLinkIconFont)
								Text(page.title)
							}
							.font(sourceLinkFont)
							.foregroundStyle(Color.accentColor)
						}
						.accessibilityLabel("Open \(page.title) documentation")
					}
					ForEach(message.sourceWebLinks) { webLink in
						Link(destination: webLink.url) {
							HStack(spacing: 6) {
								Image(systemName: "globe")
									.font(sourceLinkIconFont)
								Text(webLink.title)
							}
							.font(sourceLinkFont)
							.foregroundStyle(Color.accentColor)
						}
						.accessibilityLabel("Open \(webLink.title) on meshtastic.org")
					}
				}
				.padding(.leading, avatarWidth)
			}
		}
	}

	private func extractMeshtasticWebLinks(from markdown: String) -> [ChirpyWebLink] {
		var results: [ChirpyWebLink] = []

		func appendIfNeeded(title: String, urlString: String) {
			guard let url = URL(string: urlString) else { return }
			guard let host = url.host?.lowercased(), host.hasSuffix("meshtastic.org") else { return }
			guard !isFeedWebURL(url) else { return }
			guard !isLegalWebURL(url) else { return }
			let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
			let finalTitle: String
			if cleanedTitle.isEmpty {
				let pathPart = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
				finalTitle = pathPart.isEmpty ? "meshtastic.org" : pathPart
			} else {
				finalTitle = cleanedTitle
			}
			let link = ChirpyWebLink(title: finalTitle, url: url)
			if !results.contains(link) {
				results.append(link)
			}
		}

		let markdownPattern = "\\[([^\\]]+)\\]\\((https?://(?:www\\.)?meshtastic\\.org[^\\s\\)]+)\\)"
		if let markdownRegex = try? NSRegularExpression(pattern: markdownPattern) {
			let fullRange = NSRange(markdown.startIndex..., in: markdown)
			let matches = markdownRegex.matches(in: markdown, range: fullRange)
			for match in matches {
				guard match.numberOfRanges == 3,
					let titleRange = Range(match.range(at: 1), in: markdown),
					let urlRange = Range(match.range(at: 2), in: markdown)
				else {
					continue
				}
				appendIfNeeded(
					title: String(markdown[titleRange]),
					urlString: String(markdown[urlRange])
				)
			}
		}

		let plainURLPattern = "https?://(?:www\\.)?meshtastic\\.org[^\\s<>()\\[\\]\"']*"
		if let plainURLRegex = try? NSRegularExpression(pattern: plainURLPattern) {
			let fullRange = NSRange(markdown.startIndex..., in: markdown)
			let matches = plainURLRegex.matches(in: markdown, range: fullRange)
			for match in matches {
				guard let urlRange = Range(match.range, in: markdown) else { continue }
				let rawURL = String(markdown[urlRange])
				let trimmedURL = rawURL.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;"))
				appendIfNeeded(title: "", urlString: trimmedURL)
			}
		}

		return results
	}

	private var thinkingBubble: some View {
		HStack(alignment: .bottom, spacing: 8) {
			chirpyAvatarSmall
			HStack(spacing: 6) {
				ProgressView()
					.progressViewStyle(.circular)
					.scaleEffect(0.75)
				Text("Thinking…")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 14)
			.padding(.vertical, 10)
			.background(Color(uiColor: .secondarySystemBackground))
			.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
			Spacer(minLength: 56)
		}
	}

	private func errorBanner(_ text: String) -> some View {
		HStack(spacing: 8) {
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.orange)
			Text(text)
				.font(.subheadline)
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.orange.opacity(0.12))
		.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
	}

	private var chirpyAvatarSmall: some View {
		return Image("Chirpy")
			.resizable()
			.scaledToFit()
			.frame(width: chirpyAvatarSize * chirpyAspect, height: chirpyAvatarSize)
			.accessibilityHidden(true)
	}

	// MARK: Input bar

	/// Converts a markdown string to an `AttributedString` for rich rendering in `Text` views.
	private func markdownAttributedString(_ markdown: String) -> AttributedString {
		do {
			let attributed = try AttributedString(
				markdown: markdown,
				options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
			)
			return attributed
		} catch {
			return AttributedString(markdown)
		}
	}

	private var inputBar: some View {
		HStack(alignment: .bottom, spacing: 8) {
			TextField("Ask Chirpy…", text: $query, axis: .vertical)
				.lineLimit(1...5)
				.padding(.horizontal, 12)
				.padding(.vertical, 8)
				.background(Color(uiColor: .secondarySystemBackground))
				.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
				.focused($isInputFocused)
				.submitLabel(.send)
				.onSubmit { Task { await sendQuery() } }
				.accessibilityLabel("Question input")
			Button {
				Task { await sendQuery() }
			} label: {
				Image(systemName: "arrow.up.circle.fill")
					.font(.system(size: 32))
					.foregroundStyle(
						query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
							? Color(uiColor: .tertiaryLabel)
							: Color.accentColor
					)
			}
			.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
			.accessibilityLabel(isLoading ? "Chirpy is loading an answer" : "Send question to Chirpy")
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(Color(uiColor: .systemBackground))
	}

	// MARK: - Query execution

	@MainActor
	private func sendQuery() async {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, !isLoading else { return }

		query = ""
		errorMessage = nil
		messages.append(ChirpyMessage(isUser: true, text: trimmed))
		isLoading = true

		defer { isLoading = false }

		let contextPages = bundle.retrievePages(for: trimmed)
		let localContext = buildContext(pages: contextPages)
		let shouldUseWebAugmentation = shouldUseWebAugmentation(query: trimmed, pages: contextPages)
		let webSnippets = shouldUseWebAugmentation ? await fetchWebFallbackSnippets(for: trimmed) : []
		let webContext = buildWebContext(snippets: webSnippets)
		let combinedContext: String
		if localContext.isEmpty {
			combinedContext = webContext
		} else if webContext.isEmpty {
			combinedContext = localContext
		} else {
			combinedContext = "\(localContext)\n\n\(webContext)"
		}

		do {
			var answer = try await runLanguageModel(question: trimmed, context: combinedContext, pages: contextPages)
			let firstPassEntities = suspiciousUngroundedEntities(answer: answer, question: trimmed, context: combinedContext, pages: contextPages)
			if firstPassEntities.score >= groundingScoreThreshold {
				Logger.docs.warning("AI grounding check flagged first response; retrying with strict grounding")
				let strictAnswer = try await runLanguageModel(
					question: trimmed,
					context: combinedContext,
					pages: contextPages,
					strictGrounding: true
				)
				let strictPassEntities = suspiciousUngroundedEntities(answer: strictAnswer, question: trimmed, context: combinedContext, pages: contextPages)
				if strictPassEntities.score >= groundingScoreThreshold {
					Logger.docs.warning("AI grounding check flagged strict retry; returning grounded fallback")
					answer = "I couldn't confidently ground that answer in the documentation I have. Please try rephrasing your question, or open one of the linked docs pages for verified details."
				} else {
					answer = strictAnswer
				}
			}

			// Merge pages the model used as context with any pages it mentioned by name in the response.
			// This handles cases where the model says e.g. "check the Nodes List page" — we surface
			// a direct link even if that page wasn't in the top retrieved context pages.
			let compareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
			let mentionedPages = bundle.allPages().filter { page in
				answer.range(of: page.title, options: compareOptions) != nil
			}
			var linkedPages = contextPages
			for page in mentionedPages where !linkedPages.contains(where: { $0.id == page.id }) {
				linkedPages.append(page)
			}
			var webLinks = extractMeshtasticWebLinks(from: answer)
			for snippet in webSnippets {
				let link = ChirpyWebLink(title: snippet.title, url: snippet.url)
				if !webLinks.contains(link) {
					webLinks.append(link)
				}
			}
			webLinks.sort { lhs, rhs in
				let lhsPriority = webURLPriority(lhs.url)
				let rhsPriority = webURLPriority(rhs.url)
				if lhsPriority != rhsPriority {
					return lhsPriority < rhsPriority
				}
				return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
			}
			if webLinks.contains(where: { isContentWebURL($0.url) }) {
				webLinks.removeAll { isSearchWebURL($0.url) }
			}
			webLinks.removeAll { isFeedWebURL($0.url) }
			webLinks.removeAll { isLegalWebURL($0.url) }
			if webLinks.contains(where: { isContentWebURL($0.url) && !isIntroductionWebURL($0.url) }) {
				webLinks.removeAll { isIntroductionWebURL($0.url) }
			}
			messages.append(ChirpyMessage(isUser: false, text: answer, sourcePages: linkedPages, sourceWebLinks: webLinks))
			Logger.docs.info("AI assistant answered query using \(contextPages.count) local pages; \(webSnippets.count) web snippets; web augmentation \(shouldUseWebAugmentation ? "enabled" : "skipped"); \(linkedPages.count) local links; \(webLinks.count) web links")
		} catch {
			errorMessage = "Could not generate an answer. Please try again."
			Logger.docs.error("AI assistant error: \(error.localizedDescription)")
		}
	}

	// Balanced heuristic: score suspicious proper nouns that are absent from question/context/page titles.
	private func suspiciousUngroundedEntities(answer: String, question: String, context: String, pages: [DocPage]) -> (entities: [String], score: Int) {
		let candidatePattern = "\\b[A-Z][A-Za-z]{2,}(?:\\s+[A-Z][A-Za-z]{2,})?\\b"
		guard let regex = try? NSRegularExpression(pattern: candidatePattern) else { return ([], 0) }

		let allowedTerms: Set<String> = [
			"meshtastic", "chirpy", "bluetooth", "lora", "mqtt", "tak", "ios", "iphone", "ipad", "apple"
		]
		let commonCapitalizedWords: Set<String> = [
			"the", "this", "that", "these", "those", "you", "your", "we", "our", "it", "its",
			"when", "where", "what", "why", "how", "if", "for", "and", "or", "but", "try",
			"open", "check", "please", "docs", "documentation", "settings", "messages", "nodes", "map"
		]

		let pageTitleText = pages.map(\ .title).joined(separator: " ").lowercased()
		let searchableCorpus = "\(question.lowercased()) \(context.lowercased()) \(pageTitleText)"
		let range = NSRange(answer.startIndex..., in: answer)
		let matches = regex.matches(in: answer, range: range)
		var suspicious: [String] = []
		var totalScore = 0

		for match in matches {
			guard let wordRange = Range(match.range, in: answer) else { continue }
			let candidate = answer[wordRange].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
			if candidate.count < 4 { continue }
			if allowedTerms.contains(candidate) { continue }
			if commonCapitalizedWords.contains(candidate) { continue }
			if candidate.contains("http") || candidate.contains("www") { continue }
			if candidate.hasSuffix(".org") || candidate.hasSuffix(".com") { continue }
			if searchableCorpus.contains(candidate) { continue }

			suspicious.append(candidate)
			totalScore += candidate.contains(" ") ? 2 : 1
		}

		return (Array(Set(suspicious)), totalScore)
	}

	private func shouldUseWebAugmentation(query: String, pages: [DocPage]) -> Bool {
		if !directIntentURLs(for: query).isEmpty {
			return true
		}

		guard hasStrongLocalRetrieval(for: query, pages: pages) else {
			return true
		}

		Logger.docs.info("AI web augmentation skipped for strong local retrieval")
		return false
	}

	private func hasStrongLocalRetrieval(for query: String, pages: [DocPage]) -> Bool {
		guard pages.count >= 2 else { return false }
		let terms = query.lowercased()
			.components(separatedBy: .whitespacesAndNewlines)
			.flatMap { $0.components(separatedBy: .punctuationCharacters) }
			.filter { $0.count >= 3 }
		guard !terms.isEmpty else { return false }

		let keywordSet = Set(pages.flatMap { $0.keywords.map { $0.lowercased() } })
		let matched = terms.filter { term in keywordSet.contains(where: { keyword in keyword == term || keyword.hasPrefix(term) }) }
		let matchRatio = Double(matched.count) / Double(terms.count)
		return matchRatio >= 0.6
	}

	private func buildWebContext(snippets: [ChirpyWebSnippet]) -> String {
		guard !snippets.isEmpty else { return "" }
		return snippets.map { snippet in
			"## Website: \(snippet.title)\nURL: \(snippet.url.absoluteString)\n\(snippet.content)"
		}.joined(separator: "\n\n")
	}

	private func buildContext(pages: [DocPage]) -> String {
		pages.map { page in
			let pageText = (try? String(contentsOf: page.htmlURL, encoding: .utf8))?
				.replacingOccurrences(of: "<script[\\s\\S]*?<\\/script>", with: " ", options: .regularExpression)
				.replacingOccurrences(of: "<style[\\s\\S]*?<\\/style>", with: " ", options: .regularExpression)
				.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
				.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
				.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			return "## \(page.title)\n\(String(pageText.prefix(2000)))"
		}.joined(separator: "\n\n")
	}

	private func fetchWebFallbackSnippets(for query: String) async -> [ChirpyWebSnippet] {
		guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
			let searchURL = URL(string: "https://meshtastic.org/search/?q=\(encodedQuery)")
		else {
			return []
		}

		guard let host = searchURL.host?.lowercased(), host.hasSuffix("meshtastic.org") else { return [] }

		let intentURLs = directIntentURLs(for: query)
		let shouldSkipSearchSnippet = !intentURLs.isEmpty
		let includeIntroduction = isIntroductionQuery(query)
		let searchHTML = await fetchWebHTML(from: searchURL)
		let searchSnippet: ChirpyWebSnippet?
		if shouldSkipSearchSnippet {
			searchSnippet = nil
		} else if let searchHTML {
			searchSnippet = buildWebSnippet(fromHTML: searchHTML, url: searchURL, title: "meshtastic.org search results")
		} else {
			searchSnippet = nil
		}
		let resultURLs = searchHTML.map { extractMeshtasticResultURLs(from: $0, relativeTo: searchURL) } ?? []
		let filteredResultURLs = includeIntroduction ? resultURLs : resultURLs.filter { !isIntroductionWebURL($0) }
		let candidateURLs = Array((intentURLs + filteredResultURLs).prefix(2))

		let pageSnippets = await withTaskGroup(of: ChirpyWebSnippet?.self, returning: [ChirpyWebSnippet].self) { group in
			for url in candidateURLs {
				group.addTask {
					await self.fetchWebSnippet(at: url, title: self.webSnippetTitle(for: url))
				}
			}
			var collected: [ChirpyWebSnippet] = []
			for await snippet in group {
				if let snippet {
					collected.append(snippet)
				}
			}
			return collected
		}

		var snippets: [ChirpyWebSnippet] = []
		for snippet in pageSnippets where !snippets.contains(where: { $0.url == snippet.url }) {
			snippets.append(snippet)
		}
		if let searchSnippet,
			!snippets.contains(where: { isContentWebURL($0.url) }),
			!snippets.contains(where: { $0.url == searchSnippet.url }) {
			snippets.append(searchSnippet)
		}
		if !includeIntroduction,
			snippets.contains(where: { isContentWebURL($0.url) && !isIntroductionWebURL($0.url) }) {
			snippets.removeAll { isIntroductionWebURL($0.url) }
		}

		if snippets.isEmpty {
			Logger.docs.info("AI web fallback unavailable — continuing with local docs only")
		}
		return snippets
	}

	private func directIntentURLs(for query: String) -> [URL] {
		if isBlogQuery(query), let blogURL = URL(string: "https://meshtastic.org/blog/") {
			return [blogURL]
		}
		return []
	}

	private func isBlogQuery(_ query: String) -> Bool {
		let normalized = query.lowercased()
		let blogTerms = ["blog", "news", "announcement", "announcements"]
		return blogTerms.contains(where: { normalized.contains($0) })
	}

	private func webSnippetTitle(for url: URL) -> String {
		if url.path.lowercased().hasPrefix("/blog") {
			return "meshtastic.org blog"
		}
		return "meshtastic.org"
	}

	private func extractMeshtasticResultURLs(from html: String, relativeTo searchURL: URL) -> [URL] {
		let hrefPattern = "href=\"([^\"]+)\""
		guard let regex = try? NSRegularExpression(pattern: hrefPattern) else { return [] }

		let range = NSRange(html.startIndex..., in: html)
		let matches = regex.matches(in: html, range: range)
		var urls: [URL] = []

		for match in matches {
			guard match.numberOfRanges > 1,
				let hrefRange = Range(match.range(at: 1), in: html)
			else {
				continue
			}

			let href = String(html[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
			guard !href.isEmpty else { continue }
			guard let url = URL(string: href, relativeTo: searchURL)?.absoluteURL else { continue }
			guard let host = url.host?.lowercased(), host.hasSuffix("meshtastic.org") else { continue }
			guard !shouldSkipWebFallbackURL(url) else { continue }
			guard !urls.contains(url) else { continue }
			urls.append(url)
		}

		return urls.sorted { lhs, rhs in
			let lhsPriority = webURLPriority(lhs)
			let rhsPriority = webURLPriority(rhs)
			if lhsPriority != rhsPriority {
				return lhsPriority < rhsPriority
			}
			return lhs.absoluteString.localizedCaseInsensitiveCompare(rhs.absoluteString) == .orderedAscending
		}
	}

	private func isContentWebURL(_ url: URL) -> Bool {
		let path = url.path.lowercased()
		if path.hasPrefix("/blog/") {
			return true
		}
		if path.hasPrefix("/docs/") {
			return !path.hasPrefix("/docs/category/") && path != "/docs/"
		}
		return false
	}

	private func webURLPriority(_ url: URL) -> Int {
		if isContentWebURL(url) {
			return 0
		}
		let path = url.path.lowercased()
		if path == "/search/" {
			return 2
		}
		return 1
	}

	private func isSearchWebURL(_ url: URL) -> Bool {
		url.path.lowercased() == "/search/"
	}

	private func isFeedWebURL(_ url: URL) -> Bool {
		let path = url.path.lowercased()
		return path.hasSuffix("/atom.xml") || path.hasSuffix("/rss.xml")
	}

	private func isIntroductionWebURL(_ url: URL) -> Bool {
		let path = url.path.lowercased()
		return path == "/docs/introduction/"
			|| path.contains("/docs/introduction/")
			|| path.contains("/docs/getting-started/")
	}

	private func isIntroductionQuery(_ query: String) -> Bool {
		let normalized = query.lowercased()
		let introductionTerms = ["introduction", "intro", "getting started", "what is meshtastic", "new to meshtastic"]
		return introductionTerms.contains(where: { normalized.contains($0) })
	}

	private func isLegalWebURL(_ url: URL) -> Bool {
		let path = url.path.lowercased()
		let components = url.pathComponents
			.map { $0.lowercased() }
			.filter { $0 != "/" }
		let legalTerms = ["legal", "privacy", "terms", "tos"]
		return path == "/legal"
			|| path.hasPrefix("/legal/")
			|| path == "/privacy"
			|| path.hasPrefix("/privacy/")
			|| path == "/terms"
			|| path.hasPrefix("/terms/")
			|| components.contains(where: { legalTerms.contains($0) })
	}

	private func shouldSkipWebFallbackURL(_ url: URL) -> Bool {
		let path = url.path.lowercased()
		let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
		let hasSearchQuery = queryItems.contains(where: { $0.name == "q" && !($0.value ?? "").isEmpty })
		let isQuerylessSearch = path == "/search/" && !hasSearchQuery

		return path.contains("/docs/category/apple-apps")
			|| path.contains("/docs/software/apple-apps")
			|| isQuerylessSearch
			|| isFeedWebURL(url)
			|| isLegalWebURL(url)
	}

	private func fetchWebSnippet(at url: URL, title: String) async -> ChirpyWebSnippet? {
		guard let host = url.host?.lowercased(), host.hasSuffix("meshtastic.org") else { return nil }
		guard !shouldSkipWebFallbackURL(url) else { return nil }

		guard let html = await fetchWebHTML(from: url) else { return nil }
		return buildWebSnippet(fromHTML: html, url: url, title: title)
	}

	private func buildWebSnippet(fromHTML html: String, url: URL, title: String) -> ChirpyWebSnippet? {
		let plainText = sanitizeHTML(html)
		guard !plainText.isEmpty else { return nil }
		let finalTitle = url.lastPathComponent.isEmpty ? title : url.lastPathComponent
		return ChirpyWebSnippet(title: finalTitle, url: url, content: String(plainText.prefix(1500)))
	}

	private func fetchWebHTML(from url: URL) async -> String? {
		var request = URLRequest(url: url)
		request.timeoutInterval = 2
		request.cachePolicy = .returnCacheDataElseLoad

		do {
			let (data, response) = try await URLSession.shared.data(for: request)
			guard let http = response as? HTTPURLResponse else { return nil }
			guard (200...299).contains(http.statusCode) else {
				Logger.docs.info("AI web fallback skipped for \(url.absoluteString, privacy: .public) — HTTP \(http.statusCode)")
				return nil
			}
			guard let html = String(data: data, encoding: .utf8) else {
				Logger.docs.info("AI web fallback skipped for \(url.absoluteString, privacy: .public) — encoding failure")
				return nil
			}
			return html
		} catch {
			Logger.docs.info("AI web fallback skipped for \(url.absoluteString, privacy: .public) — \(error.localizedDescription)")
			return nil
		}
	}

	private func sanitizeHTML(_ html: String) -> String {
		html
			.replacingOccurrences(of: "<script[\\s\\S]*?<\\/script>", with: " ", options: .regularExpression)
			.replacingOccurrences(of: "<style[\\s\\S]*?<\\/style>", with: " ", options: .regularExpression)
			.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Language model

	@MainActor
	private func runLanguageModel(question: String, context: String, pages: [DocPage], strictGrounding: Bool = false) async throws -> String {
		#if canImport(FoundationModels)
		return try await runWithContext(question: question, context: context, pages: pages, strictGrounding: strictGrounding)
		#else
		return "AI assistance is not available on this device."
		#endif
	}

	#if canImport(FoundationModels)
	@available(iOS 26, *)
	@MainActor
	private func runWithContext(
		question: String,
		context: String,
		pages: [DocPage],
		isRetry: Bool = false,
		strictGrounding: Bool = false
	) async throws -> String {
		guard await FoundationModelAvailability.shared.isAvailable else {
			return "AI assistance is temporarily unavailable on this device. Please try again later."
		}
		let pageList = pages.map { "- \($0.title)" }.joined(separator: "\n")
		let strictGroundingInstruction = strictGrounding
			? "Every proper noun, product name, and organization name in your reply must already appear in the provided context. If not, omit it and say the docs do not provide that detail."
			: ""
		let systemInstruction = """
		You are Chirpy, the cheerful and enthusiastic AI assistant for the Meshtastic iOS app. \
		You love mesh networking and get genuinely excited helping people learn about it! \
		Use a warm, upbeat tone — sprinkle in the occasional mesh-themed pun or encouragement \
		like "Happy meshing!" or "That's a great question — let's dig into the docs!" \
		Keep answers concise but friendly. Use emoji sparingly (one or two per reply max). \
		Answer questions using ONLY the provided documentation context. \
		If the context includes website snippets, cite those pages using plain meshtastic.org URLs in your answer. \
		If the answer cannot be found in the provided context, say something like: \
		"Hmm, I couldn't find that in the docs I have! Try browsing the documentation pages directly, \
		or check out meshtastic.org for more details. 📡" \
		\(strictGroundingInstruction) \
		Do not use any outside knowledge or pre-trained facts. \
		When suggesting next steps, encourage the user to explore related features in the app.
		"""
		let prompt = """
		Pages used:
		\(pageList)

		Documentation context:
		\(context)

		Question: \(question)
		"""
		do {
			let lmSession = LanguageModelSession(instructions: systemInstruction)
			let result = try await lmSession.respond(to: prompt)
			return result.content
		} catch {
			await FoundationModelAvailability.shared.reportFailure(error)
			// Retry with a single top page if this is not already a retry (handles context overflow errors)
			if !isRetry && pages.count > 1 {
				Logger.docs.warning("AI query failed — retrying with top 1 page: \(error.localizedDescription)")
				let topPage = Array(pages.prefix(1))
				let reducedContext = buildContext(pages: topPage)
				return try await runWithContext(
					question: question,
					context: reducedContext,
					pages: topPage,
					isRetry: true,
					strictGrounding: strictGrounding
				)
			}
			throw error
		}
	}
	#endif
}
