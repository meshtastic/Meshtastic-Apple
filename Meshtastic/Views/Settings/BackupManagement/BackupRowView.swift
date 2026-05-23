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
