//
//  BackupManagement.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2025.
//

import SwiftUI
import OSLog
import SwiftData

/// Settings screen showing all node backups with total storage usage and swipe-to-delete.
struct BackupManagement: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@State private var backups: [BackupEntry] = []
	@State private var totalSize: Int64 = 0
	@State private var showDeleteConfirmation = false
	@State private var entryToDelete: BackupEntry?
	@State private var isRestoringBackup = false
	@State private var restoreErrorMessage: String?

	private var showsInlineDeleteButton: Bool {
		#if targetEnvironment(macCatalyst)
		true
		#else
		false
		#endif
	}

	private var showsInlineRestoreButton: Bool {
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
							showRestoreButton: showsInlineRestoreButton,
							showDeleteButton: showsInlineDeleteButton,
							onRestore: {
								Task {
									await restoreBackup(entry)
								}
							},
							onDelete: {
								entryToDelete = entry
								showDeleteConfirmation = true
							}
						)
						.contextMenu {
							Button {
								Task {
									await restoreBackup(entry)
								}
							} label: {
								Label("Restore", systemImage: "arrow.counterclockwise")
							}

							Button(role: .destructive) {
								entryToDelete = entry
								showDeleteConfirmation = true
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
						#if !targetEnvironment(macCatalyst)
							.swipeActions(edge: .trailing, allowsFullSwipe: false) {
								Button {
									Task {
										await restoreBackup(entry)
									}
								} label: {
									Label("Restore", systemImage: "arrow.counterclockwise")
								}

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
		.disabled(isRestoringBackup)
		.overlay {
			if isRestoringBackup {
				ZStack {
					Color.black.opacity(0.2)
						.ignoresSafeArea()

					VStack(spacing: 14) {
						ProgressView()
							.controlSize(.large)
						Text("Restoring Backup")
							.font(.headline)
					}
					.padding(.horizontal, 28)
					.padding(.vertical, 22)
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
				}
			}
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
		.alert("Restore Failed", isPresented: Binding(
			get: { restoreErrorMessage != nil },
			set: { if !$0 { restoreErrorMessage = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(restoreErrorMessage ?? "")
		}
	}

	@MainActor
	private func refreshBackups() {
		backups = NodeBackupManager.shared.listBackups()
		totalSize = NodeBackupManager.shared.totalBackupSize
	}

	@MainActor
	private func restoreBackup(_ entry: BackupEntry) async {
		isRestoringBackup = true
		defer {
			isRestoringBackup = false
		}

		let restoreResult = await backupCurrentAndRestoreDatabase(
			forNode: entry.nodeNum,
			accessoryManager: accessoryManager,
			appState: accessoryManager.appState,
			selectedTab: .settings,
			disconnectCurrentDevice: true
		)

		switch restoreResult {
		case .success:
			refreshBackups()
		case .skipped(let reason):
			restoreErrorMessage = reason
		case .noBackupFound:
			restoreErrorMessage = "No backup was found for this node."
		}
	}
}

#Preview {
	NavigationStack {
		BackupManagement()
	}
}
