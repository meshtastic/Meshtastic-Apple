// Meshtastic/Views/Settings/HelpAndDocumentation/DocBrowserView.swift

import SwiftUI
import OSLog

struct DocBrowserView: View {

	@State private var searchText = ""
	@State private var isAIPresented = false
	@State private var translatedLabels: [String: String] = [:]
	@State private var labelTranslationTask: Task<Void, Never>?

	private let bundle = DocBundle.shared

	private var pages: [DocPage] {
		bundle.allPages()
	}

	private func translatedSectionName(_ section: DocSection) -> String {
		translatedLabels["section:\(section.rawValue)"] ?? section.displayName
	}

	private func translatedPageTitle(_ page: DocPage) -> String {
		translatedLabels["page:\(page.id)"] ?? page.title
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
		return DocSection.allCases.compactMap { section in
			let matching = pages.filter { page in
				let translatedTitle = translatedPageTitle(page).lowercased()
				return page.section == section && (
					translatedTitle.contains(lowered) ||
					page.title.lowercased().contains(lowered) ||
					page.keywords.contains { $0.lowercased().contains(lowered) }
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
			startLabelTranslations()
			Logger.docs.debug("DocBrowserView appeared — \(pages.count) pages loaded")
		}
		.onDisappear {
			labelTranslationTask?.cancel()
			labelTranslationTask = nil
		}
		.onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
			translatedLabels = [:]
			startLabelTranslations()
		}
		.onReceive(NotificationCenter.default.publisher(for: DocTranslationService.languageBecameAvailableNotification)) { _ in
			// Language pack just finished downloading — clear stale failures and retry
			Task {
				await DocTranslationService.shared.clearUIStringCache()
			}
			translatedLabels = [:]
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
			var updates: [String: String] = [:]
			let service = DocTranslationService.shared

			updates["navTitle"] = await service.translatedUIString("Help & Docs", targetLanguage: languageCode)
			updates["searchPrompt"] = await service.translatedUIString("Search docs", targetLanguage: languageCode)

			await withTaskGroup(of: (String, String).self) { group in
				for section in DocSection.allCases {
					group.addTask {
						let translated = await service.translatedUIString(section.displayName, targetLanguage: languageCode)
						return ("section:\(section.rawValue)", translated)
					}
				}

				for page in capturedPages {
					group.addTask {
						let translated = await service.translatedUIString(page.title, targetLanguage: languageCode)
						return ("page:\(page.id)", translated)
					}
				}

				for await (key, value) in group {
					updates[key] = value
				}
			}

			guard !Task.isCancelled else { return }
			await MainActor.run {
				translatedLabels = updates
			}
		}
	}
}
