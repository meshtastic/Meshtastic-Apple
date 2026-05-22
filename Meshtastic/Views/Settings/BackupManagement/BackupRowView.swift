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

	var body: some View {
		HStack {
			Image(systemName: "cylinder.split.1x2")
				.symbolRenderingMode(.hierarchical)
				.font(.title2)
				.foregroundColor(.accentColor)
				.frame(width: 35)

			VStack(alignment: .leading, spacing: 4) {
				Text(entry.nodeName ?? "Node \(entry.nodeNum)")
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
		}
		.padding(.vertical, 4)
	}

	private var formattedSize: String {
		ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file)
	}
}
