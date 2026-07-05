// MentionAutocomplete.swift
// Meshtastic

import SwiftData
import SwiftUI

/// A compact autocomplete panel shown when the user types `@` in the compose field.
///
/// Displays up to 10 known nodes filtered by the current query (matched against long name,
/// short name, and user ID). Tapping a row calls `onSelect` with the chosen `UserEntity`,
/// which the caller inserts as `@!<hex-id>` into the message text.
struct MentionAutocomplete: View {

	@Query(sort: \NodeInfoEntity.num) private var nodes: [NodeInfoEntity]

	let query: String
	let onSelect: (UserEntity) -> Void

	private var filteredNodes: [NodeInfoEntity] {
		let trimmed = query.lowercased()
		let candidates = trimmed.isEmpty
			? nodes
			: nodes.filter { node in
				let user = node.user
				let longName = (user?.longName ?? "").lowercased()
				let shortName = (user?.shortName ?? "").lowercased()
				let userId = (user?.userId ?? "").lowercased()
				return longName.contains(trimmed)
					|| shortName.contains(trimmed)
					|| userId.contains(trimmed)
			}
		return Array(candidates.prefix(10))
	}

	var body: some View {
		if !filteredNodes.isEmpty {
			VStack(spacing: 0) {
				Divider()
				ScrollView(.vertical, showsIndicators: false) {
					LazyVStack(spacing: 0) {
						ForEach(filteredNodes, id: \.num) { node in
							if let user = node.user {
								Button {
									onSelect(user)
								} label: {
									MentionAutocompleteRow(node: node)
								}
								.buttonStyle(.plain)
								Divider()
									.padding(.leading, 56)
							}
						}
					}
				}
				.frame(maxHeight: 200)
				.background(Color(.systemBackground))
			}
			.transition(.opacity.combined(with: .move(edge: .bottom)))
		}
	}
}

// MARK: - MentionAutocompleteRow

private struct MentionAutocompleteRow: View {
	let node: NodeInfoEntity

	var body: some View {
		HStack(spacing: 12) {
			CircleText(
				text: node.user?.shortName ?? "?",
				color: Color(UIColor(hex: UInt32(node.num))),
				circleSize: 36
			)
			VStack(alignment: .leading, spacing: 2) {
				Text(node.user?.longName ?? "Unknown")
					.font(.body)
					.foregroundStyle(.primary)
				if let userId = node.user?.userId {
					Text(userId)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			Spacer()
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.contentShape(Rectangle())
	}
}
