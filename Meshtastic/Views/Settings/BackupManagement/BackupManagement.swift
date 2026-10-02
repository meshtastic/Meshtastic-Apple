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
	/// The radio this window works with (feature 021, D-19).
	@Environment(\.windowRadio) private var windowRadio
	@EnvironmentObject private var router: Router
	@State private var backups: [BackupEntry] = []
	@State private var totalSize: Int64 = 0
	@State private var showDeleteConfirmation = false
	@State private var entryToDelete: BackupEntry?
	@State private var isRestoringBackup = false
	@State private var restoreErrorMessage: String?
	/// A restore waiting for the user to confirm it replaces several radios' data (T166).
	@State private var entryToRestore: BackupEntry?
	@State private var radiosReplacedByRestore: [StoredRadio] = []
	@State private var isBackingUp = false
	@State private var backupErrorMessage: String?

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
					ForEach(backups, id: \.key) { entry in
						BackupRowView(
							entry: entry,
							showRestoreButton: showsInlineRestoreButton,
							showDeleteButton: showsInlineDeleteButton,
							onRestore: {
								Task {
									await requestRestore(entry)
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
									await requestRestore(entry)
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
										await requestRestore(entry)
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
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Button {
					Task { await backupNow() }
				} label: {
					Label("Backup Now", systemImage: "swiftdata")
						.symbolEffect(.pulse, isActive: isBackingUp)
				}
				.disabled(isBackingUp || isRestoringBackup)
				.accessibilityLabel(String(localized: "Backup Now", comment: "VoiceOver label for the backup now button"))
			}
		}
		.onAppear {
			refreshBackups()
		}
		.alert("Backup Failed", isPresented: Binding(
			get: { backupErrorMessage != nil },
			set: { if !$0 { backupErrorMessage = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(backupErrorMessage ?? "")
		}
		.disabled(isRestoringBackup || isBackingUp)
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
		.alert("Restore Backup?", isPresented: Binding(
			get: { entryToRestore != nil },
			set: { if !$0 { entryToRestore = nil } }
		), presenting: entryToRestore) { entry in
			Button("Restore", role: .destructive) {
				Task { await restoreBackup(entry) }
			}
			Button("Cancel", role: .cancel) {}
		} message: { entry in
			Text("Restoring \(entry.nodeName ?? "Node \(entry.nodeNum)")'s backup replaces the data of all your radios: \(ListFormatter.localizedString(byJoining: radiosReplacedByRestore.map(\.name))). They disconnect first.")
		}
		.alert("Delete Backup?", isPresented: $showDeleteConfirmation, presenting: entryToDelete) { entry in
			Button("Delete", role: .destructive) {
				Task { @MainActor in
					NodeBackupManager.shared.deleteBackup(forKey: entry.key)
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
	/// With one radio's data in the store a restore starts straight away, as it always has.
	/// With several, the user first confirms that every radio's data is replaced (T166).
	private func requestRestore(_ entry: BackupEntry) async {
		let radios = await MeshPackets.shared.storedRadios()
		guard radios.count > 1 else {
			await restoreBackup(entry)
			return
		}
		radiosReplacedByRestore = radios
		entryToRestore = entry
	}

	private func restoreBackup(_ entry: BackupEntry) async {
		isRestoringBackup = true
		defer {
			isRestoringBackup = false
		}

		// Resolve the outgoing node before the flow disconnects anything.
		let currentNodeNum = accessoryManager.nodeNum(for: windowRadio) ?? {
			let num = accessoryManager.radioNodeNum(for: windowRadio)
			return num > 0 ? num : nil
		}()
		let restoreResult = await backupCurrentAndRestoreDatabase(
			forNode: entry.nodeNum,
			currentNodeNum: currentNodeNum,
			accessoryManager: accessoryManager,
			appState: accessoryManager.appState,
			router: router,
			selectedTab: .settings,
			disconnectCurrentDevice: true
		)

		switch restoreResult {
		case .success:
			// The restored rows are that radio's; attribute them now, before a background pass
			// could credit them to whichever radio is preferred then (T162).
			await accessoryManager.handshakeGate.acquire()
			do {
				try await MeshPackets.shared.drainMultiRadioBackfill(ownRadio: entry.nodeNum)
			} catch {
				Logger.data.error("💥 [MultiRadio] Backfill after restore failed: \(error.localizedDescription, privacy: .public)")
			}
			accessoryManager.handshakeGate.release()
			refreshBackups()
		case .skipped(let reason):
			restoreErrorMessage = reason
		case .noBackupFound:
			restoreErrorMessage = "No backup was found for this node."
		}
	}

	@MainActor
	private func backupNow() async {
		let nodeNum: Int64? = accessoryManager.nodeNum(for: windowRadio) ?? {
			let num = accessoryManager.radioNodeNum(for: windowRadio)
			return num > 0 ? num : nil
		}()
		guard let nodeNum else {
			backupErrorMessage = "No connected node found to back up."
			return
		}
		let nodeName = accessoryManager.devices.first(where: { $0.num == nodeNum })?.longName
		isBackingUp = true
		defer { isBackingUp = false }

		let result = await NodeBackupManager.shared.createBackup(
			forNode: nodeNum,
			deviceId: accessoryManager.connectedDeviceId,
			nodeName: nodeName
		)
		switch result {
		case .success:
			refreshBackups()
		case .skipped(let reason):
			backupErrorMessage = reason
		case .noBackupFound:
			backupErrorMessage = "Backup could not be created."
		}
	}
}

#Preview {
	NavigationStack {
		BackupManagement()
	}
}
