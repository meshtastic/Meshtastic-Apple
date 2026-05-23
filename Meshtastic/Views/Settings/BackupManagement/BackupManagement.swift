//
//  BackupManagementView.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import SwiftUI
import OSLog

/// Settings screen showing all node backups with total storage usage and swipe-to-delete.
struct BackupManagement: View {
	@State private var backups: [BackupEntry] = []
	@State private var totalSize: Int64 = 0
	@State private var showDeleteConfirmation = false
	@State private var entryToDelete: BackupEntry?

	private var showsInlineDeleteButton: Bool {
		#if targetEnvironment(macCatalyst)
		true
		#else
		false
		#endif
	}

	var body: some View {
		List {
			// Total storage section
			Section {
				HStack {
					Label {
						Text("Total Backup Storage")
					} icon: {
						Image(systemName: "externaldrive")
					}
					Spacer()
					Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
						.foregroundColor(.secondary)
				}
			}

			// Backup list section
			Section(header: Text("Node Backups")) {
				if backups.isEmpty {
					Text("No backups available")
						.foregroundColor(.secondary)
						.italic()
				} else {
					ForEach(backups, id: \.nodeNum) { entry in
						BackupRowView(
							entry: entry,
							showDeleteButton: showsInlineDeleteButton,
							onDelete: {
								entryToDelete = entry
								showDeleteConfirmation = true
							}
						)
						.contextMenu {
							Button(role: .destructive) {
								entryToDelete = entry
								showDeleteConfirmation = true
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
						#if !targetEnvironment(macCatalyst)
							.swipeActions(edge: .trailing, allowsFullSwipe: false) {
								Button(role: .destructive) {
									entryToDelete = entry
									showDeleteConfirmation = true
								} label: {
									Label("Delete", systemImage: "trash")
								}
							}
						#endif
					}
				}
			}
		}
		.navigationTitle("Backup Management")
		.navigationBarTitleDisplayMode(.inline)
		.onAppear {
			refreshBackups()
		}
		.alert("Delete Backup?", isPresented: $showDeleteConfirmation, presenting: entryToDelete) { entry in
			Button("Delete", role: .destructive) {
				Task { @MainActor in
					NodeBackupManager.shared.deleteBackup(forNode: entry.nodeNum)
					refreshBackups()
				}
			}
			Button("Cancel", role: .cancel) {}
		} message: { entry in
			Text("This will permanently delete the backup for \(entry.nodeName ?? "Node \(entry.nodeNum)") and free \(ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file)) of storage.")
		}
	}

	@MainActor
	private func refreshBackups() {
		backups = NodeBackupManager.shared.listBackups()
		totalSize = NodeBackupManager.shared.totalBackupSize
	}
}

#Preview {
	NavigationStack {
		BackupManagement()
	}
}
