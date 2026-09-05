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
				HStack {
					Text(entry.createdAt, style: .date)
					Text("•")
					Text(entry.createdAt, style: .time)
					Text("•")
					// Node numbers change on the 2.8 upgrade, so a backup keyed on one is orphaned by
					// the upgrade. Showing which entries are keyed by device and which are still
					// waiting to be is the only way to see that from here.
					if entry.deviceId == nil {
						Text(entry.nodeNum.toHex())
					} else {
						Label(entry.nodeNum.toHex(), systemImage: "checkmark.seal")
							.labelStyle(.titleAndIcon)
					}
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
