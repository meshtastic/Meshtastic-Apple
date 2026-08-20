import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct UF2MaintenanceView: View {
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context

	let node: NodeInfoEntity

	@StateObject private var coordinator: UF2MaintenanceCoordinator
	@State private var isSelectingVolume = false
	@State private var showStopTrackingConfirmation = false

	init(firmwareFile: FirmwareFile, node: NodeInfoEntity, request: UF2MaintenanceRequest) {
		self.init(
			descriptor: UF2MaintenanceApplicationDescriptor(firmwareFile: firmwareFile),
			node: node,
			request: request
		)
	}

	init(
		descriptor: UF2MaintenanceApplicationDescriptor,
		node: NodeInfoEntity,
		request: UF2MaintenanceRequest
	) {
		self.node = node
		_coordinator = StateObject(
			wrappedValue: UF2MaintenanceCoordinator(descriptor: descriptor, request: request)
		)
	}

	var body: some View {
		NavigationStack {
			List {
				operationSection
				dfuSection
				writeSection
				statusSection
			}
			.navigationTitle(coordinator.activeRequest.displayName)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") {
						coordinator.cancelBeforeWrite()
						dismiss()
					}
					.disabled(coordinator.blocksDismissal)
				}
			}
		}
		.interactiveDismissDisabled(coordinator.blocksDismissal)
		.confirmationDialog(
			"Stop tracking this recovery?",
			isPresented: $showStopTrackingConfirmation,
			titleVisibility: .visible
		) {
			Button("Stop Tracking Recovery", role: .destructive) {
				coordinator.stopTrackingRecovery()
			}
		} message: {
			Text("Only stop after you have confirmed the radio boots. This does not retry either UF2 write.")
		}
		.fileImporter(
			isPresented: $isSelectingVolume,
			allowedContentTypes: [.folder],
			allowsMultipleSelection: false
		) { result in
			handleFolderSelection(result)
		}
		.task {
			setIdleTimerDisabled(true)
			await coordinator.prepare()
		}
		.onDisappear {
			coordinator.cancelBeforeWrite()
			setIdleTimerDisabled(false)
		}
	}

	private var operationSection: some View {
		Section("Firmware Maintenance") {
			LabeledContent("Operation", value: coordinator.activeRequest.displayName)
			LabeledContent("Application", value: coordinator.activeDescriptor.fileName)
			LabeledContent("Version", value: coordinator.activeDescriptor.version)
			LabeledContent("Target", value: coordinator.activeDescriptor.platformioTarget)
			if coordinator.activeRequest == .factoryErase {
				Label(
					"This permanently erases the radio's filesystem, owner, channels, keys, and settings before reinstalling firmware.",
					systemImage: "exclamationmark.triangle.fill"
				)
				.foregroundStyle(.red)
			} else {
				Text("The OTAFIX image is selected only from the Board-ID reported by the mounted UF2 volume.")
			}
			Text("The application firmware is validated before the first write. Maintenance always requires a second UF2 pass to reinstall it.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	private var dfuSection: some View {
		Section("1. Connect the UF2 volume") {
			Text("Enter DFU manually if the radio cannot boot. Each pass requires a freshly mounted UF2 volume.")
			Button {
				sendEnterDFUMode()
			} label: {
				Label("Send Reboot into DFU", systemImage: "square.and.arrow.down")
			}
			.disabled(accessoryManager.activeDeviceNum == nil)
		}
	}

	private var writeSection: some View {
		Section("2. Validate and write") {
			Button {
				coordinator.selectVolume()
				isSelectingVolume = true
			} label: {
				Label(writeButtonTitle, systemImage: "externaldrive.badge.checkmark")
			}
			.buttonStyle(.borderedProminent)
			.disabled(!coordinator.canSelectVolume)
		}
	}

	private var writeButtonTitle: LocalizedStringKey {
		if coordinator.state == .awaitingApplicationWrite {
			return "Choose UF2 Volume and Reinstall Firmware"
		}
		return coordinator.activeRequest == .factoryErase
			? "Choose UF2 Volume and Erase"
			: "Choose UF2 Volume and Upgrade Bootloader"
	}

	@ViewBuilder
	private var statusSection: some View {
		Section("Status") {
			switch coordinator.state {
			case .idle:
				Text("Waiting to prepare maintenance.")
			case .preparing:
				ProgressView("Validating the application firmware…")
			case .ready:
				Label("Ready for the maintenance pass.", systemImage: "checkmark.circle.fill")
					.foregroundStyle(.green)
			case .selectingVolume:
				Text("Choose the mounted UF2 bootloader folder in Files.")
			case .loadingMaintenance:
				ProgressView("Loading and verifying the pinned maintenance image…")
			case .writing:
				ProgressView("Writing the UF2 image. Keep the radio connected…")
			case .awaitingApplicationWrite:
				Label(
					"The maintenance write was attempted. Do not retry it. Reinstall the application firmware now.",
					systemImage: "exclamationmark.triangle.fill"
				)
				.foregroundStyle(.orange)
				if let artifact = coordinator.maintenanceArtifact {
					LabeledContent("Maintenance file", value: artifact.fileName)
					LabeledContent("SHA-256", value: artifact.sha256)
						.font(.caption.monospaced())
						.textSelection(.enabled)
				}
				if let error = coordinator.maintenanceCopyError {
					Text("Files reported: \(error)").font(.caption)
				}
			case .awaitingReconnect:
				Label(
					"The application write was attempted. Do not retry it. Reconnect the radio and verify the firmware.",
					systemImage: "arrow.triangle.2.circlepath"
				)
				if let error = coordinator.applicationCopyError {
					Text("Files reported: \(error)").font(.caption)
				}
				Button("Verify Reconnected Radio") {
					coordinator.verify(reportedFirmwareVersion: liveNode()?.metadata?.firmwareVersion)
				}
				.disabled(liveNode()?.metadata?.firmwareVersion == nil)
			case .verifying:
				ProgressView("Checking the reported firmware version…")
			case .completed(let warnings):
				Label("Application firmware verified.", systemImage: "checkmark.seal.fill")
					.foregroundStyle(.green)
				ForEach(warnings, id: \.self) { warning in
					Text(warning).foregroundStyle(.orange)
				}
			case .failed(let message):
				Label(message, systemImage: "xmark.octagon.fill")
					.foregroundStyle(.red)
			}

			if let warning = coordinator.warningMessage {
				Text(warning).font(.caption).foregroundStyle(.orange)
			}
			if let error = coordinator.errorMessage {
				Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
			}
			if coordinator.canStopTracking {
				Button("Stop Tracking Recovery", role: .destructive) {
					showStopTrackingConfirmation = true
				}
			}
		}
	}

	private func handleFolderSelection(_ result: Result<[URL], Error>) {
		switch result {
		case .success(let urls):
			guard let folderURL = urls.first else {
				coordinator.volumeSelectionCancelled()
				return
			}
			Task { await coordinator.write(to: folderURL) }
		case .failure(let error):
			coordinator.volumeSelectionFailed(error)
		}
	}

	private func sendEnterDFUMode() {
		guard let currentNode = liveNode(), let user = currentNode.user else { return }
		Task {
			do {
				try await accessoryManager.sendEnterDfuMode(fromUser: user, toUser: user)
			} catch {
				Logger.mesh.error("Reboot into DFU failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	private func liveNode() -> NodeInfoEntity? {
		getNodeInfo(id: accessoryManager.activeDeviceNum ?? 0, context: context)
	}

	private func setIdleTimerDisabled(_ disabled: Bool) {
		#if canImport(UIKit)
		UIApplication.shared.isIdleTimerDisabled = disabled
		#endif
	}
}
