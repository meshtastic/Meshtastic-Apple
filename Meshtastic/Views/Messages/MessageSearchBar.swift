//
//  MessageSearchBar.swift
//  Meshtastic
//
//  Shared "find in conversation" results bar for ChannelMessageList / UserMessageList:
//  live match count + current index and previous/next navigation. The search field itself
//  is provided by each list's `.searchable` modifier; this bar sits just beneath it while
//  a query is active.
//

import SwiftUI

struct MessageSearchBar: View {
	/// Total number of matches for the current query.
	let matchCount: Int
	/// Zero-based index of the currently-focused match, or -1 when there are none.
	let currentIndex: Int
	var onPrevious: () -> Void
	var onNext: () -> Void

	var body: some View {
		HStack(spacing: 16) {
			Text(positionText)
				.font(.caption)
				.monospacedDigit()
				.foregroundStyle(.secondary)
				.accessibilityLabel(
					matchCount == 0
						? String(localized: "No matches", comment: "VoiceOver: no search matches found")
						: String(localized: "Match \(currentIndex + 1) of \(matchCount)", comment: "VoiceOver: current match position out of the total match count")
				)

			Spacer()

			Button(action: onPrevious) {
				Image(systemName: "chevron.up")
			}
			.disabled(matchCount == 0)
			.accessibilityLabel(String(localized: "Previous match", comment: "VoiceOver label for the previous search match button"))

			Button(action: onNext) {
				Image(systemName: "chevron.down")
			}
			.disabled(matchCount == 0)
			.accessibilityLabel(String(localized: "Next match", comment: "VoiceOver label for the next search match button"))
		}
		.buttonStyle(.borderless)
		.padding(.horizontal)
		.padding(.vertical, 8)
		.background(.bar)
	}

	private var positionText: String {
		matchCount == 0 ? "No matches" : "\(currentIndex + 1) of \(matchCount)"
	}
}
