//
//  PowerChannelLabels.swift
//  Meshtastic
//
//  User-assignable labels for the three INA-style power-monitor channels, so a user can tell
//  which line is e.g. solar / battery / load instead of a generic "Channel 1/2/3". Labels are
//  per-node and persisted in UserDefaults. (Issue #2046)
//

import SwiftUI

enum PowerChannelLabelStore {
	static let channelCount = 3

	static func key(nodeNum: Int64, channel: Int) -> String {
		"powerChannelLabel.\(nodeNum).\(channel)"
	}

	/// The user-assigned label for a channel, or nil when none is set.
	static func customLabel(nodeNum: Int64, channel: Int, store: UserDefaults = .standard) -> String? {
		let value = store.string(forKey: key(nodeNum: nodeNum, channel: channel))?
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return (value?.isEmpty ?? true) ? nil : value
	}

	/// The default, non-customized label for a channel ("Channel 1", "Channel 2", …). Uses the
	/// existing discrete catalog keys (already translated) rather than a `%lld` format string.
	static func defaultLabel(channel: Int) -> String {
		switch channel {
		case 0: return String(localized: "Channel 1")
		case 1: return String(localized: "Channel 2")
		default: return String(localized: "Channel 3")
		}
	}

	/// The label to display: the user's override when set, otherwise the default.
	static func displayLabel(nodeNum: Int64, channel: Int, store: UserDefaults = .standard) -> String {
		customLabel(nodeNum: nodeNum, channel: channel, store: store) ?? defaultLabel(channel: channel)
	}

	/// Sets (or, when blank/nil, clears) the label for a channel.
	static func setLabel(_ label: String?, nodeNum: Int64, channel: Int, store: UserDefaults = .standard) {
		let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
		if let trimmed, !trimmed.isEmpty {
			store.set(trimmed, forKey: key(nodeNum: nodeNum, channel: channel))
		} else {
			store.removeObject(forKey: key(nodeNum: nodeNum, channel: channel))
		}
	}
}

/// Sheet for renaming the three power-monitor channels on a node.
struct PowerChannelLabelEditor: View {
	let nodeNum: Int64
	var onSave: () -> Void

	@Environment(\.dismiss) private var dismiss
	@State private var labels: [String]

	init(nodeNum: Int64, onSave: @escaping () -> Void) {
		self.nodeNum = nodeNum
		self.onSave = onSave
		_labels = State(initialValue: (0..<PowerChannelLabelStore.channelCount).map {
			PowerChannelLabelStore.customLabel(nodeNum: nodeNum, channel: $0) ?? ""
		})
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					ForEach(0..<PowerChannelLabelStore.channelCount, id: \.self) { channel in
						TextField(PowerChannelLabelStore.defaultLabel(channel: channel), text: $labels[channel])
							.autocorrectionDisabled()
					}
				} header: {
					Text("Channel Labels")
				} footer: {
					Text("Name each power channel (e.g. Solar, Battery, Load). Leave blank to use the default.")
				}
			}
			.navigationTitle("Rename Channels")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						for channel in 0..<PowerChannelLabelStore.channelCount {
							PowerChannelLabelStore.setLabel(labels[channel], nodeNum: nodeNum, channel: channel)
						}
						onSave()
						dismiss()
					}
				}
			}
		}
	}
}
