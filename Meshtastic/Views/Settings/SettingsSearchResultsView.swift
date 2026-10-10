//
//  SettingsSearchResultsView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/13/26.
//
import SwiftUI

/// The Settings list while a search is active.
///
/// Replaces the list in place rather than pushing a results screen, so clearing the
/// field returns the user exactly where they were. Results are grouped by the same
/// sections the full list uses, so a result sits where the user would have found it
/// by scrolling.
struct SettingsSearchResultsView: View {
	let results: [SettingsSearchResult]
	let docs: [DocumentationSearch.Page]
	/// Opens the result's screen. A plain `NavigationLink` cannot do it: the row names a
	/// control as well as a screen, and only the tap knows which one was chosen.
	let onSelect: (SettingsSearchEntry) -> Void

	var body: some View {
		if results.isEmpty && docs.isEmpty {
			ContentUnavailableView.search
		} else {
			// compactMap drops sections with no matches rather than rendering empty
			// headers, the same way the documentation browser filters its catalogue.
			ForEach(SettingsListSection.allCases, id: \.self) { section in
				let matches = results.filter { $0.entry.listSection == section }
				if !matches.isEmpty {
					Section(section.title) {
						ForEach(matches) { result in
							Button {
								onSelect(result.entry)
							} label: {
								HStack {
									row(for: result)
									Spacer(minLength: 8)
									// A Button has no disclosure indicator of its own, and
									// these rows push a screen like the ones above them.
									Image(systemName: "chevron.forward")
										.font(.footnote.weight(.semibold))
										.foregroundStyle(.tertiary)
										.accessibilityHidden(true)
								}
							}
							.buttonStyle(.plain)
						}
					}
				}
			}

			// Documentation last, under its own heading, and never dimmed: a page
			// reads the same with or without a radio.
			if !docs.isEmpty {
				Section(String(localized: "Help & Documentation", comment: "Search results section")) {
					ForEach(docs) { page in
						NavigationLink(value: SettingsNavigationState.helpDocs) {
							VStack(alignment: .leading, spacing: 2) {
								Text(page.title)
									.font(.body)
								Text(String(localized: "Documentation", comment: "Search result breadcrumb"))
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							.padding(.vertical, 2)
							.frame(minHeight: 44, alignment: .leading)
						}
					}
				}
			}
		}
	}

	@ViewBuilder
	private func row(for result: SettingsSearchResult) -> some View {
		let dimmed: Bool = {
			if case .deEmphasised = result.visibility { return true }
			return false
		}()

		VStack(alignment: .leading, spacing: 2) {
			Text(result.entry.label)
				.font(.body)
			// The breadcrumb is not decoration: "Enabled" labels six different
			// controls, so the screen and section are what tell them apart.
			Text(breadcrumb(for: result.entry))
				.font(.caption)
				.foregroundStyle(.secondary)
			if case .deEmphasised(let reason) = result.visibility {
				Text(reason)
					.font(.caption2)
					.foregroundStyle(.tertiary)
			}
		}
		.padding(.vertical, 2)
		// 44pt is the minimum comfortable target, and the row must survive the
		// largest Dynamic Type size without clipping.
		.frame(minHeight: 44, alignment: .leading)
		.opacity(dimmed ? 0.55 : 1)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(accessibilityLabel(for: result))
	}

	private func breadcrumb(for entry: SettingsSearchEntry) -> String {
		guard let section = entry.sectionTitle, !section.isEmpty else { return entry.screenTitle }
		return "\(entry.screenTitle) › \(section)"
	}

	private func accessibilityLabel(for result: SettingsSearchResult) -> String {
		var parts = [result.entry.label, breadcrumb(for: result.entry)]
		if case .deEmphasised(let reason) = result.visibility { parts.append(reason) }
		return parts.joined(separator: ", ")
	}
}
