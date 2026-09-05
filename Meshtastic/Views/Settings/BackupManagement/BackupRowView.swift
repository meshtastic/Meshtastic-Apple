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

	var body: some View {
		HStack {
			Image(systemName: "cylinder.split.1x2")
				.symbolRenderingMode(.hierarchical)
				.font(.title2)
				.foregroundColor(.accentColor)
				.frame(width: 35)

			VStack(alignment: .leading, spacing: 4) {
				Text(entry.nodeName ?? entry.nodeNum.toHex())
					.font(.headline)

				// Both identifiers, because they answer different questions. The node number is what
				// the radio reports now and changes on the 2.8 upgrade; the device id is the hardware
				// identifier the backup is filed under and does not. An entry with no device id has
				// not been reconnected since this changed and is still keyed by node number.
				HStack(spacing: 4) {
					Text(entry.nodeNum.toHex())
					if let deviceId = entry.deviceId {
						Text("•")
						Image(systemName: "checkmark.seal")
						Text(deviceId)
							.lineLimit(1)
							.truncationMode(.middle)
					}
				}
				.font(.caption.monospaced())
				.foregroundColor(.secondary)
				.accessibilityElement(children: .combine)
				.accessibilityLabel(
					entry.deviceId == nil
					? String(localized: "Node \(entry.nodeNum.toHex()), keyed by node number")
					: String(localized: "Node \(entry.nodeNum.toHex()), keyed by device \(entry.deviceId ?? "")")
				)

				HStack {
					Text(entry.createdAt, style: .date)
					Text("•")
					Text(entry.createdAt, style: .time)
				}
				.font(.caption)
				.foregroundColor(.secondary)
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
