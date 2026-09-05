//
//  BackupRowView.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import SwiftUI

/// Displays a single backup entry with node name, backup date, and formatted file size.
struct BackupRowView: View {
	let entry: BackupEntry
	var showRestoreButton = false
	var showDeleteButton = false
	var onRestore: (() -> Void)?
	var onDelete: (() -> Void)?

	/// Spoken form of the identity line — two bare hex strings read aloud are meaningless.
	private var identityDescription: String {
		if let deviceId = entry.deviceId {
			return String(localized: "Node \(entry.nodeNum.toHex()), keyed by device \(deviceId)")
		}
		return String(localized: "Node \(entry.nodeNum.toHex()), keyed by node number")
	}

	var body: some View {
		HStack {
			Image(systemName: "cylinder.split.1x2")
				.symbolRenderingMode(.hierarchical)
				.font(.title2)
				.foregroundColor(.accentColor)
				.frame(width: 35)

			VStack(alignment: .leading, spacing: 2) {
				Text(entry.nodeName ?? entry.nodeNum.toHex())
					.font(.headline)
					.lineLimit(1)

				// The two identifiers answer different questions: the node number is what the radio
				// reports now and changes on the 2.8 upgrade, the device id is what the backup is
				// filed under and does not. The node number only repeats here when the headline shows
				// a name instead.
				if entry.nodeName != nil {
					Text(entry.nodeNum.toHex())
						.font(.caption.monospaced())
						.foregroundColor(.secondary)
						.lineLimit(1)
				}

				// Its own line and never truncated — a partial device id cannot be checked against
				// anything, which is the only reason to show it. Scales down to fit instead.
				// No device id means this radio has not been reconnected since backups moved off
				// node numbers, so it is still keyed by one.
				if let deviceId = entry.deviceId {
					HStack(spacing: 4) {
						Image(systemName: "checkmark.seal")
						Text(deviceId)
							.lineLimit(1)
							.minimumScaleFactor(0.5)
					}
					.font(.caption2.monospaced())
					.foregroundColor(.secondary)
					.accessibilityElement(children: .combine)
					.accessibilityLabel(identityDescription)
				}

				// One string rather than date and time as separate views, which wrapped mid-line.
				Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
					.font(.caption)
					.foregroundColor(.secondary)
					.lineLimit(1)
			}

			Spacer()

			Text(formattedSize)
				.font(.subheadline)
				.foregroundColor(.secondary)

			if showRestoreButton, let onRestore {
				Button(action: onRestore) {
					Image(systemName: "arrow.counterclockwise")
				}
				.buttonStyle(.borderless)
				.accessibilityLabel(String(localized: "Restore backup", comment: "VoiceOver label for the restore backup button"))
			}

			if showDeleteButton, let onDelete {
				Button(role: .destructive, action: onDelete) {
					Image(systemName: "trash")
				}
				.buttonStyle(.borderless)
			}
		}
		.padding(.vertical, 4)
	}

	private var formattedSize: String {
		ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file)
	}
}
