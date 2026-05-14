// WMeshtastic/Views/Settings/HelpAndDocumentation/AIDocAssistantView.swift

import SwiftUI
import OSLog
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
		let pattern = "\\[([^\\]]+)\\]\\((https?://(?:www\\.)?meshtastic\\.org[^\\s\\)]+)\\)"
		guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
		let fullRange = NSRange(markdown.startIndex..., in: markdown)
		let matches = regex.matches(in: markdown, range: fullRange)
		var results: [ChirpyWebLink] = []
		for match in matches {
			guard match.numberOfRanges == 3,
				let titleRange = Range(match.range(at: 1), in: markdown),
				let urlRange = Range(match.range(at: 2), in: markdown)
			else {
				continue
			}
			let title = String(markdown[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
			let urlString = String(markdown[urlRange])
			guard let url = URL(string: urlString) else { continue }
			let link = ChirpyWebLink(title: title.isEmpty ? url.lastPathComponent : title, url: url)
			if !results.contains(link) {
				results.append(link)
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
		let context = buildContext(pages: contextPages)

		do {
			let answer = try await runLanguageModel(question: trimmed, context: context)
			// Merge pages the model used as context with any pages it mentioned by name in the response.
			// This handles cases where the model says e.g. "check the Nodes List page" — we surface
			// a direct link even if that page wasn't in the top retrieved context pages.
			let mentionedPages = bundle.allPages().filter { page in
				answer.range(of: page.title, options: [.caseInsensitive, .diacriticInsensitive]) != nil
			}
			var linkedPages = contextPages
			for page in mentionedPages where !linkedPages.contains(where: { $0.id == page.id }) {
				linkedPages.append(page)
			}
			let webLinks = extractMeshtasticWebLinks(from: answer)
			messages.append(ChirpyMessage(isUser: false, text: answer, sourcePages: linkedPages, sourceWebLinks: webLinks))
			Logger.docs.info("AI assistant answered query using \(contextPages.count) context pages; \(linkedPages.count) local links; \(webLinks.count) web links")
		} catch {
			errorMessage = "Could not generate an answer. Please try again."
			Logger.docs.error("AI assistant error: \(error.localizedDescription)")
		}
	}

	private func buildContext(pages: [DocPage]) -> String {
		guard !pages.isEmpty else {
			return "No specific documentation context available."
		}
		return pages.compactMap { page -> String? in
			guard let html = try? String(contentsOf: page.htmlURL, encoding: .utf8) else { return nil }
			// Strip HTML tags for plain-text context
			let plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
			return "## \(page.title)\n\(plain.trimmingCharacters(in: .whitespacesAndNewlines))"
		}.joined(separator: "\n\n")
	}

	@MainActor
	private func runLanguageModel(question: String, context: String) async throws -> String {
		#if canImport(FoundationModels)
		return try await runWithContext(question: question, context: context, pages: bundle.retrievePages(for: question))
		#else
		return "AI assistance is not available on this device."
		#endif
	}

	#if canImport(FoundationModels)
	@available(iOS 26, *)
	@MainActor
	private func runWithContext(question: String, context: String, pages: [DocPage], isRetry: Bool = false) async throws -> String {
		let pageList = pages.map { "- \($0.title)" }.joined(separator: "\n")
		let systemInstruction = """
		You are Chirpy, the cheerful and enthusiastic AI assistant for the Meshtastic iOS app. \
		You love mesh networking and get genuinely excited helping people learn about it! \
		Use a warm, upbeat tone — sprinkle in the occasional mesh-themed pun or encouragement \
		like "Happy meshing!" or "That's a great question — let's dig into the docs!" \
		Keep answers concise but friendly. Use emoji sparingly (one or two per reply max). \
		Answer questions using ONLY the provided documentation context. \
		If the answer cannot be found in the provided context, say something like: \
		"Hmm, I couldn't find that in the docs I have! Try browsing the documentation pages directly, \
		or check out meshtastic.org for more details. 📡" \
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
			// Retry with a single top page if this is not already a retry (handles context overflow errors)
			if !isRetry && pages.count > 1 {
				Logger.docs.warning("AI query failed — retrying with top 1 page: \(error.localizedDescription)")
				let topPage = Array(pages.prefix(1))
				let reducedContext = buildContext(pages: topPage)
				return try await runWithContext(question: question, context: reducedContext, pages: topPage, isRetry: true)
			}
			throw error
		}
	}
	#endif
}
