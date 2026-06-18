// Meshtastic/Views/Settings/HelpAndDocumentation/DocBrowserView.swift

import SwiftUI
import OSLog

struct DocBrowserView: View {

	@State private var searchText = ""
	/// Collapsible section state — User Guide expanded by default, Developer Guide collapsed.
	@State private var expandedSections: Set<DocSection> = [.user]
	@State private var translatedLabels: [String: String] = [:]
	@State private var labelTranslationTask: Task<Void, Never>?
	@State private var translationProgress: String?
	@State private var prefetchTask: Task<Void, Never>?

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
				// Try downloading community translations first, then start full prefetch
				prefetchTask = Task {
					let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
					if languageCode != "en" {
						let built = await CommunityTranslationFetcher.shared.buildTranslatedFolder(languageCode: languageCode)
						if built {
							await MainActor.run {
								bundle.load()
							}
						}
						// Start full translation pipeline: dev docs → user docs → nav labels
						if !isUsingTranslatedFolder {
							await DocTranslationService.shared.prefetchAll()
						}
					}
					// Refresh nav labels from cache after prefetch completes
					await MainActor.run {
						startLabelTranslations()
					}
				}
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
			.accessibilityHint("Opens \(translatedPageTitle(page)) documentation")
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
		.accessibilityValue(expansion.wrappedValue ? "Expanded" : "Collapsed")
		.accessibilityHint(expansion.wrappedValue ? "Double tap to collapse" : "Double tap to expand")
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

			// Try to fetch community nav labels and search index (fast CDN download)
			await CommunityTranslationFetcher.shared.fetchNavLabels(languageCode: languageCode)
			await CommunityTranslationFetcher.shared.fetchSearchIndex(languageCode: languageCode)

			let postFetchLabels = await MainActor.run { translatedLabels }

			var updates: [String: String] = [:]

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
}
