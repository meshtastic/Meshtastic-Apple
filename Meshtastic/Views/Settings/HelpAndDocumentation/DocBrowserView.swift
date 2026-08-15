// Meshtastic/Views/Settings/HelpAndDocumentation/DocBrowserView.swift

import SwiftUI
import OSLog
#if !targetEnvironment(macCatalyst)
import Translation
#endif

struct DocBrowserView: View {

	@State private var searchText = ""
	/// Collapsible section state — User Guide expanded by default, Developer Guide collapsed.
	@State private var expandedSections: Set<DocSection> = [.user]
	@State private var translatedLabels: [String: String] = [:]
	@State private var labelTranslationTask: Task<Void, Never>?
	@State private var translationProgress: String?
	@State private var prefetchTask: Task<Void, Never>?
	/// Language code that the docs can be translated into but whose Apple Translation pack isn't
	/// installed yet. Non-nil drives the "download language pack" prompt.
	@State private var needsLanguagePack: String?
	/// Language code currently being downloaded — non-nil activates the download `translationTask`.
	@State private var downloadingLanguage: String?

	private let bundle = DocBundle.shared

	/// True when DocBundle loaded from pre-rendered translated folder — titles are already translated.
	private var isUsingTranslatedFolder: Bool {
		bundle.loadedLanguage != "en"
	}

	private var pages: [DocPage] {
		bundle.allPages()
	}

	private func translatedSectionName(_ section: DocSection) -> String {
		translatedLabels["section:\(section.rawValue)"] ?? section.displayName
	}

	private func translatedPageTitle(_ page: DocPage) -> String {
		// When using translated folder, page.title is already translated from the index
		if isUsingTranslatedFolder { return page.title }
		return translatedLabels["page:\(page.id)"] ?? page.title
	}

	private var translatedNavigationTitle: String {
		translatedLabels["navTitle"] ?? "Help & Documentation"
	}

	private var translatedSearchPrompt: String {
		translatedLabels["searchPrompt"] ?? "Search docs"
	}

	/// Expansion binding for a collapsible guide section. While a search is
	/// active, sections are forced open so matches in an otherwise-collapsed
	/// section are never hidden.
	private func sectionExpansion(_ section: DocSection) -> Binding<Bool> {
		Binding(
			get: { !searchText.isEmpty || expandedSections.contains(section) },
			set: { isExpanded in
				if isExpanded {
					expandedSections.insert(section)
				} else {
					expandedSections.remove(section)
				}
			}
		)
	}

	private var filteredSections: [(section: DocSection, pages: [DocPage])] {
		if searchText.isEmpty {
			return bundle.pagesBySection()
		}
		let lowered = searchText.lowercased()
		let languageCode = Bundle.main.documentationLanguageCode
		let searchIndex = bundle.searchIndex(for: languageCode)
		let searchEntryById = Dictionary(
			(searchIndex ?? []).map { ($0.id, $0) },
			uniquingKeysWith: { first, _ in first }
		)
		return DocSection.allCases.compactMap { section in
			let matching = pages.filter { page in
				let translatedTitle = translatedPageTitle(page).lowercased()
				let translatedEntry = searchEntryById[page.id]
				let translatedKeywords = translatedEntry?.keywords ?? []
				return page.section == section && (
					translatedTitle.contains(lowered) ||
					page.title.lowercased().contains(lowered) ||
					page.keywords.contains { $0.lowercased().contains(lowered) } ||
					translatedKeywords.contains { $0.lowercased().contains(lowered) }
				)
			}
			return matching.isEmpty ? nil : (section: section, pages: matching)
		}
	}

	var body: some View {
		Group {
			if pages.isEmpty {
				ContentUnavailableView(
					"Documentation Unavailable",
					systemImage: "book.closed",
					description: Text("The documentation bundle could not be loaded.")
				)
			} else {
				VStack(spacing: 0) {
					if let translationProgress {
						HStack(spacing: 12) {
							ProgressView()
								.controlSize(.regular)
							VStack(alignment: .leading, spacing: 2) {
								Text("Translation in progress…")
									.font(.headline)
								Text(translationProgress)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							Spacer()
						}
						.padding(.horizontal)
						.padding(.vertical, 10)
						.background(.bar)
					}
					if let needsLanguagePack {
						languageDownloadBanner(languageCode: needsLanguagePack)
					}
					List {
						ForEach(filteredSections, id: \.section) { item in
							let expansion = sectionExpansion(item.section)
							#if targetEnvironment(macCatalyst)
							// Mac Catalyst gets the native collapsible section; `.sidebar` (below)
							// renders its disclosure toggle.
							Section(translatedSectionName(item.section), isExpanded: expansion) {
								pageRows(item.pages)
							}
							#else
							// iOS uses `.insetGrouped`, which silently drops `Section(isExpanded:)`'s
							// toggle — leaving the collapsed-by-default Developer section unreachable.
							// A custom tappable header restores collapse/expand on iOS.
							Section {
								if expansion.wrappedValue {
									pageRows(item.pages)
								}
							} header: {
								sectionHeader(item.section, expansion: expansion)
							}
							#endif
						}
					}
					#if targetEnvironment(macCatalyst)
					.listStyle(.sidebar)
					#else
					.listStyle(.insetGrouped)
					#endif
				}
			}
		}
		.navigationTitle(translatedNavigationTitle)
		.navigationBarTitleDisplayMode(.large)
		.askChirpyToolbar()
		.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: translatedSearchPrompt)
		.onAppear {
			bundle.load()
			if isUsingTranslatedFolder {
				// Already have translated folder — just translate the few UI chrome strings
				startLabelTranslations()
			} else {
				kickoffTranslation()
			}
			Logger.docs.debug("DocBrowserView appeared — \(pages.count) pages loaded")
		}
		.onDisappear {
			prefetchTask?.cancel()
		}
		.onReceive(NotificationCenter.default.publisher(for: DocTranslationService.translationProgressDidChange)) { _ in
			Task {
				let progress = await DocTranslationService.shared.translationProgress
				await MainActor.run {
					switch progress {
					case .idle:
						translationProgress = nil
					case .translating(let completed, let total, let description):
						translationProgress = "\(description) - \(completed)/\(total)"
						// Refresh labels from cache so titles appear as pages complete
						startLabelTranslations()
					case .finished:
						// Pause so the final upload result is visible before dismissal
						Task {
							try? await Task.sleep(nanoseconds: 10_000_000_000)
							await MainActor.run {
								translationProgress = nil
							}
						}
					}
				}
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: DocTranslationService.navLabelsDidFinishNotification)) { _ in
			startLabelTranslations()
		}
		.onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
			translatedLabels = [:]
			startLabelTranslations()
		}
		.onReceive(NotificationCenter.default.publisher(for: DocTranslationService.languageBecameAvailableNotification)) { _ in
			// Language pack just finished downloading — retry only missing/failed labels
			Task {
				await DocTranslationService.shared.clearUIStringCache()
			}
			startLabelTranslations()
		}
			.modifier(LanguagePackDownloadModifier(
				downloadingLanguage: $downloadingLanguage,
				onDownloaded: { kickoffTranslation() }
			))
	}

	/// The navigation rows for a section's pages. Shared by the native (Catalyst) and custom (iOS)
	/// collapsible section layouts.
	@ViewBuilder
	private func pageRows(_ pages: [DocPage]) -> some View {
		ForEach(pages) { page in
			NavigationLink {
				DocPageView(page: page)
			} label: {
				pageLabel(page)
			}
			.accessibilityLabel(translatedPageTitle(page))
			.accessibilityHint(String(localized: "Opens \(translatedPageTitle(page)) documentation", comment: "VoiceOver hint for a documentation page link"))
		}
	}

	/// Tappable, collapsible section header. Replaces `Section(isExpanded:)`'s built-in toggle,
	/// which only renders with `.sidebar` (not `.insetGrouped`). The chevron rotates with the
	/// expansion state. Disabled while a search is active, since matches force every section open.
	@ViewBuilder
	private func sectionHeader(_ section: DocSection, expansion: Binding<Bool>) -> some View {
		Button {
			withAnimation(.easeInOut(duration: 0.2)) {
				expansion.wrappedValue.toggle()
			}
		} label: {
			HStack {
				Text(translatedSectionName(section))
				Spacer()
				Image(systemName: "chevron.forward")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.rotationEffect(.degrees(expansion.wrappedValue ? 90 : 0))
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.disabled(!searchText.isEmpty)
		.textCase(nil)
		.accessibilityLabel(translatedSectionName(section))
		.accessibilityValue(expansion.wrappedValue ? String(localized: "Expanded", comment: "VoiceOver value for an expanded section") : String(localized: "Collapsed", comment: "VoiceOver value for a collapsed section"))
		.accessibilityHint(expansion.wrappedValue ? String(localized: "Double tap to collapse", comment: "VoiceOver hint to collapse a section") : String(localized: "Double tap to expand", comment: "VoiceOver hint to expand a section"))
	}

	@ViewBuilder
	private func pageLabel(_ page: DocPage) -> some View {
		let title = translatedPageTitle(page)
		if page.systemImage.hasPrefix("custom.") {
			Label(title: { Text(title) }, icon: { Image(page.systemImage) })
		} else {
			Label(title, systemImage: page.systemImage)
		}
	}

	private func startLabelTranslations() {
		labelTranslationTask?.cancel()

		let languageCode = Bundle.main.documentationLanguageCode
		guard languageCode != "en", !pages.isEmpty else { return }

		let capturedPages = pages

		labelTranslationTask = Task(priority: .userInitiated) {
			let service = DocTranslationService.shared

			// Try to fetch community nav labels and search index (fast CDN download)
			await CommunityTranslationFetcher.shared.fetchNavLabels(languageCode: languageCode)
			await CommunityTranslationFetcher.shared.fetchSearchIndex(languageCode: languageCode)

			let postFetchLabels = await MainActor.run { translatedLabels }

			var updates: [String: String] = [:]

			// All candidate keys
			var allKeys: [(key: String, source: String)] = [
				("navTitle", "Help & Documentation"),
				("searchPrompt", "Search docs")
			]
			for section in DocSection.allCases {
				allKeys.append(("section:\(section.rawValue)", section.displayName))
			}
			for page in capturedPages {
				allKeys.append(("page:\(page.id)", page.title))
			}

			// Only read from cache — do not trigger on-device translation
			for item in allKeys {
				if postFetchLabels[item.key] != nil { continue }
				if let cached = await service.cachedUIString(item.source, targetLanguage: languageCode) {
					updates[item.key] = cached
				}
			}

			if !updates.isEmpty && !Task.isCancelled {
				await MainActor.run {
					for (key, value) in updates {
						translatedLabels[key] = value
					}
				}
			}
		}
	}

	/// Runs the doc translation pipeline: community CDN download first, then on-device
	/// translation if a backend is available, otherwise prompt to download the language pack.
	/// Reloads the bundle afterward so the browser switches to the translated folder in-session.
	private func kickoffTranslation() {
		prefetchTask?.cancel()
		needsLanguagePack = nil
		prefetchTask = Task {
			let languageCode = Bundle.main.documentationLanguageCode
			guard languageCode != "en" else { return }

			// Community translations need no on-device backend — try them first.
			let built = await CommunityTranslationFetcher.shared.buildTranslatedFolder(languageCode: languageCode)
			if built {
				await MainActor.run { bundle.load() }
			}

			if !isUsingTranslatedFolder {
				switch await DocTranslationService.shared.translationBackendStatus(for: languageCode) {
				case .available:
					await DocTranslationService.shared.prefetchAll()
					// prefetchAll renders a complete translated folder; reload so the browser
					// switches to it without needing a cold relaunch.
					await MainActor.run { bundle.load() }
				case .needsLanguagePack:
					await MainActor.run { needsLanguagePack = languageCode }
				case .unavailable:
					break
				}
			}

			await MainActor.run { startLabelTranslations() }
		}
	}

	/// Banner offering to download the Apple Translation language pack for the docs language.
	@ViewBuilder
	private func languageDownloadBanner(languageCode: String) -> some View {
		HStack(spacing: 12) {
			Image(systemName: "arrow.down.circle.fill")
				.font(.title2)
				.foregroundStyle(.blue)
			VStack(alignment: .leading, spacing: 2) {
				Text("Translate Documentation")
					.font(.headline)
				Text("Download the \(languageDisplayName(languageCode)) language pack to read the documentation in your language.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			if downloadingLanguage == languageCode {
				ProgressView()
			} else {
				Button("Download") { downloadingLanguage = languageCode }
					.buttonStyle(.borderedProminent)
			}
		}
		.padding(.horizontal)
		.padding(.vertical, 10)
		.background(.bar)
	}

	private func languageDisplayName(_ code: String) -> String {
		Locale.current.localizedString(forLanguageCode: code) ?? code
	}
}

// MARK: - Language Pack Download

/// Drives an Apple Translation language-pack download. When `downloadingLanguage` is set, the
/// `translationTask` activates and `prepareTranslation()` triggers the system download flow;
/// `onDownloaded` re-runs the translation pipeline once the pack is installed. Compiled to a
/// no-op on Mac Catalyst / pre-iOS 26, where the Translation framework is unavailable.
private struct LanguagePackDownloadModifier: ViewModifier {
	@Binding var downloadingLanguage: String?
	let onDownloaded: () -> Void

	func body(content: Content) -> some View {
		#if !targetEnvironment(macCatalyst)
		if #available(iOS 26, *) {
			content.translationTask(
				downloadingLanguage.map {
					TranslationSession.Configuration(
						source: Locale.Language(identifier: "en"),
						target: Locale.Language(identifier: $0))
				}
			) { session in
				do {
					try await session.prepareTranslation()
					await MainActor.run { downloadingLanguage = nil }
					onDownloaded()
				} catch {
					await MainActor.run { downloadingLanguage = nil }
					Logger.docs.error("DocBrowserView: language pack download failed: \(error.localizedDescription, privacy: .public)")
				}
			}
		} else {
			content
		}
		#else
		content
		#endif
	}
}
