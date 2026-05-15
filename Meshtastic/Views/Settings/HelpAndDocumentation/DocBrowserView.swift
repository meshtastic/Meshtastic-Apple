// Meshtastic/Views/Settings/HelpAndDocumentation/DocBrowserView.swift

import SwiftUI
import OSLog

struct DocBrowserView: View {

	@State private var searchText = ""
	@State private var isAIPresented = false
	@State private var translatedLabels: [String: String] = DocBrowserView.loadPersistedLabels()
	@State private var labelTranslationTask: Task<Void, Never>?

	private static let labelsKey = "DocBrowserTranslatedLabels"
	private static let labelsLanguageKey = "DocBrowserTranslatedLabelsLanguage"

	private static func loadPersistedLabels() -> [String: String] {
		let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
		guard languageCode != "en",
			  UserDefaults.standard.string(forKey: labelsLanguageKey) == languageCode,
			  let dict = UserDefaults.standard.dictionary(forKey: labelsKey) as? [String: String] else {
			return [:]
		}
		return dict
	}

	private func persistLabels() {
		let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
		UserDefaults.standard.set(translatedLabels, forKey: Self.labelsKey)
		UserDefaults.standard.set(languageCode, forKey: Self.labelsLanguageKey)
	}

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
		translatedLabels["navTitle"] ?? "Help & Docs"
	}

	private var translatedSearchPrompt: String {
		translatedLabels["searchPrompt"] ?? "Search docs"
	}

	private var filteredSections: [(section: DocSection, pages: [DocPage])] {
		if searchText.isEmpty {
			return bundle.pagesBySection()
		}
		let lowered = searchText.lowercased()
		let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
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
				List {
					ForEach(filteredSections, id: \.section) { item in
						Section(translatedSectionName(item.section)) {
							ForEach(item.pages) { page in
							NavigationLink {
								DocPageView(page: page)
							} label: {
								pageLabel(page)
								}
								.accessibilityLabel(translatedPageTitle(page))
								.accessibilityHint("Opens \(translatedPageTitle(page)) documentation")
							}
						}
					}
				}
				.listStyle(.insetGrouped)
			}
		}
		.navigationTitle(translatedNavigationTitle)
		.navigationBarTitleDisplayMode(.large)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				if #available(iOS 26, *) {
					Button {
						isAIPresented = true
					} label: {
						Label("Ask Chirpy", systemImage: "sparkles")
					}
					.accessibilityLabel("Ask Chirpy AI assistant")
				}
			}
		}
		.searchable(text: $searchText, prompt: translatedSearchPrompt)
		.sheet(isPresented: $isAIPresented) {
			if #available(iOS 26, *) {
				AIDocAssistantView()
			}
		}
		.onAppear {
			bundle.load()
			if isUsingTranslatedFolder {
				// Already have translated folder — just translate the few UI chrome strings
				startLabelTranslations()
			} else {
				// Try downloading community translations first, then fall back to on-device
				Task {
					let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
					if languageCode != "en" {
						let built = await CommunityTranslationFetcher.shared.buildTranslatedFolder(languageCode: languageCode)
						if built {
							await MainActor.run {
								bundle.load()
							}
						}
					}
					// Only now start label translations for any remaining UI strings
					await MainActor.run {
						startLabelTranslations()
					}
				}
			}
			Logger.docs.debug("DocBrowserView appeared — \(pages.count) pages loaded")
		}
		.onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
			translatedLabels = [:]
			UserDefaults.standard.removeObject(forKey: Self.labelsKey)
			startLabelTranslations()
		}
		.onReceive(NotificationCenter.default.publisher(for: DocTranslationService.languageBecameAvailableNotification)) { _ in
			// Language pack just finished downloading — retry only missing/failed labels
			Task {
				await DocTranslationService.shared.clearUIStringCache()
			}
			startLabelTranslations()
		}
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

		let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
		guard languageCode != "en", !pages.isEmpty else { return }

		let capturedPages = pages

		labelTranslationTask = Task(priority: .userInitiated) {
			let service = DocTranslationService.shared

			// Try to fetch community nav labels and search index first (fast CDN download)
			await CommunityTranslationFetcher.shared.fetchNavLabels(languageCode: languageCode)
			await CommunityTranslationFetcher.shared.fetchSearchIndex(languageCode: languageCode)

			// Check if community labels populated the UI string cache
			// Re-snapshot existing labels after community fetch
			let postFetchLabels = await MainActor.run { translatedLabels }

			// Pre-populate from community cache before on-device translation
			var immediateUpdates: [String: String] = [:]

			// All candidate keys
			var allKeys: [(key: String, source: String)] = [
				("navTitle", "Help & Docs"),
				("searchPrompt", "Search docs")
			]
			for section in DocSection.allCases {
				allKeys.append(("section:\(section.rawValue)", section.displayName))
			}
			for page in capturedPages {
				allKeys.append(("page:\(page.id)", page.title))
			}

			// Filter to only keys that still need translation
			var keysToTranslate: [(key: String, source: String)] = []
			for item in allKeys {
				if postFetchLabels[item.key] != nil { continue }
				if let cached = await service.cachedUIString(item.source, targetLanguage: languageCode) {
					immediateUpdates[item.key] = cached
				} else {
					keysToTranslate.append(item)
				}
			}

			// Apply any labels resolved from community cache immediately
			if !immediateUpdates.isEmpty && !Task.isCancelled {
				await MainActor.run {
					for (key, value) in immediateUpdates {
						translatedLabels[key] = value
					}
					persistLabels()
				}
			}

			guard !keysToTranslate.isEmpty else { return }

			// Translate incrementally — update the UI as each result arrives
			await withTaskGroup(of: (String, String).self) { group in
				for item in keysToTranslate {
					group.addTask {
						let translated = await service.translatedUIString(item.source, targetLanguage: languageCode)
						return (item.key, translated)
					}
				}

				for await (key, value) in group {
					guard !Task.isCancelled else { return }
					await MainActor.run {
						translatedLabels[key] = value
					}
				}
			}

			if !Task.isCancelled {
				await MainActor.run {
					persistLabels()
				}
			}
		}
	}
}
