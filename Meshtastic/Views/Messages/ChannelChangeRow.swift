//
//  ChannelChangeRow.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftUI

/// What a channel-change row says (feature 021, T377), read from the keys before and after.
enum ChannelChangeDescription {
	/// The sentence for a change from `previous` to `current` channel keys.
	static func text(previous: String?, current: String?) -> String {
		guard let previous, let current,
			  let before = ChannelIdentity.parts(of: previous),
			  let after = ChannelIdentity.parts(of: current) else {
			return String(localized: "The channel changed.", comment: "Conversation note when a radio's channel slot changed in an unknown way")
		}
		if let oldPreset = before.modemPreset, let newPreset = after.modemPreset, oldPreset != newPreset {
			let from = presetName(oldPreset)
			let to = presetName(newPreset)
			return String(localized: "Switched from \(from) to \(to).", comment: "Conversation note when the radio's modem preset changed, e.g. LongFast to LongTurbo")
		}
		if before.name != after.name {
			return String(localized: "Channel renamed from \(before.name) to \(after.name).", comment: "Conversation note when the channel in this slot got a new name")
		}
		if before.keyDigest != after.keyDigest {
			return String(localized: "The channel key changed.", comment: "Conversation note when the channel's encryption key changed")
		}
		return String(localized: "Moved to a different mesh.", comment: "Conversation note when the radio's region, frequency or radio settings changed")
	}

	private static func presetName(_ raw: Int32) -> String {
		ModemPresets(rawValue: Int(raw))?.name ?? String(raw)
	}
}

/// A channel-change row in a conversation: the radio moved this slot to another channel, so what
/// comes before is the old channel's history and what follows the new one's (T377).
struct ChannelChangeRow: View {
	let message: MessageEntity

	var body: some View {
		// A deleted row can't be read (see ChannelMessageRow).
		if message.modelContext != nil && !message.isDeleted {
			content
		} else {
			EmptyView()
		}
	}

	private var content: some View {
		ChannelChangeNote(
			text: ChannelChangeDescription.text(previous: message.previousChannelKey, current: message.channelKey),
			date: message.timestamp
		)
	}
}

/// The look of a channel-change row, separate from the model so it can be previewed and snapshotted.
struct ChannelChangeNote: View {
	let text: String
	let date: Date

	var body: some View {
		VStack(spacing: 2) {
			Label {
				Text(text)
			} icon: {
				Image(systemName: "arrow.triangle.2.circlepath")
			}
			.font(.caption)
			.foregroundStyle(.secondary)
			.multilineTextAlignment(.center)
			Text(date.formatted(date: .abbreviated, time: .shortened))
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 6)
		.background(.quaternary.opacity(0.5), in: Capsule())
		.frame(maxWidth: .infinity, alignment: .center)
		.padding(.vertical, 8)
		.accessibilityElement(children: .combine)
	}
}

#Preview {
	ChannelChangeNote(text: "Switched from LongFast to LongTurbo.", date: Date())
}
