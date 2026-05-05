// Meshtastic/Views/Settings/HelpAndDocumentation/DocBrowserView.swift

import SwiftUI
import OSLog

struct DocBrowserView: View {

	@State private var searchText = ""
	@State private var isAIPresented = false

	private let bundle = DocBundle.shared

	private var pages: [DocPage] {
		bundle.allPages()
	}

	private var filteredSections: [(section: DocSection, pages: [DocPage])] {
		if searchText.isEmpty {
			return bundle.pagesBySection()
		}
		let lowered = searchText.lowercased()
		return DocSection.allCases.compactMap { section in
			let matching = pages.filter { page in
				page.section == section && (
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
						Section(item.section.displayName) {
							ForEach(item.pages) { page in
							NavigationLink {
								DocPageView(page: page)
							} label: {
								pageLabel(page)
								}
								.accessibilityLabel(page.title)
								.accessibilityHint("Opens \(page.title) documentation")
							}
						}
					}
				}
				.listStyle(.insetGrouped)
			}
		}
		.navigationTitle("Help & Docs")
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
		.searchable(text: $searchText, prompt: "Search docs")
		.sheet(isPresented: $isAIPresented) {
			if #available(iOS 26, *) {
				AIDocAssistantView()
			}
		}
		.onAppear {
			bundle.load()
			Logger.docs.debug("DocBrowserView appeared — \(pages.count) pages loaded")
		}
	}

	@ViewBuilder
	private func pageLabel(_ page: DocPage) -> some View {
		if page.systemImage.hasPrefix("custom.") {
			Label(title: { Text(page.title) }, icon: { Image(page.systemImage) })
		} else {
			Label(page.title, systemImage: page.systemImage)
		}
	}
}
