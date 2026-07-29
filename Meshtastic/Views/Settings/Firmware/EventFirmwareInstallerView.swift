import Foundation
import SwiftUI

enum EventFirmwareInstallerPrimaryAction: Equatable {
	case install
	case webFlasher
}

enum EventFirmwareInstallerPolicy {
	static func primaryAction(
		for availability: EventFirmwareOTAAvailability
	) -> EventFirmwareInstallerPrimaryAction {
		switch availability {
		case .available:
			return .install
		case .unavailable:
			return .webFlasher
		}
	}

	static func isExpectedDeviceActive(
		expectedNodeNum: Int64,
		activeNodeNum: Int64?
	) -> Bool {
		activeNodeNum == expectedNodeNum
	}

	static func isPreparedSelectionCurrent(
		_ preparedSelection: EventFirmwareOTASelection,
		availability: EventFirmwareOTAAvailability
	) -> Bool {
		availability == .available(preparedSelection)
	}
}

struct EventFirmwareInstallerView: View {
	typealias Install = (FirmwareFile.FirmwareType, URL) -> Void

	private enum PreparationState: Equatable {
		case idle
		case preparing
		case failed(String)
	}

	@EnvironmentObject private var accessoryManager: AccessoryManager

	let event: EventFirmwareEntity
	let node: NodeInfoEntity
	let hardware: DeviceHardwareEntity
	let onInstall: Install

	private let downloader: EventFirmwareArtifactDownloader
	@State private var preparationState: PreparationState = .idle
	@State private var simulatorPreview: SimulatorFirmwarePreview?
	@State private var preparationTask: Task<Void, Never>?

	init(
		event: EventFirmwareEntity,
		node: NodeInfoEntity,
		hardware: DeviceHardwareEntity,
		downloader: EventFirmwareArtifactDownloader = EventFirmwareInstallerDependencies.downloader(),
		onInstall: @escaping Install
	) {
		self.event = event
		self.node = node
		self.hardware = hardware
		self.downloader = downloader
		self.onInstall = onInstall
	}

	var body: some View {
		List {
			Section {
				HStack(spacing: 14) {
					EventFirmwareIcon(
						edition: event.firmwareEdition ?? .vanilla,
						iconURL: event.iconURL,
						size: 48
					)

					VStack(alignment: .leading, spacing: 3) {
						Text(event.displayName ?? event.firmwareEdition?.name ?? event.edition)
							.font(.headline)
						if let dateRange = event.formattedDateRange {
							Text(dateRange)
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
						if let location = event.location, !location.isEmpty {
							Text(location)
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
					}
				}
				.padding(.vertical, 4)
			}

			Section("Firmware") {
				LabeledContent("Device", value: hardware.displayName ?? "Unknown")
				.accessibilityElement(children: .combine)
				LabeledContent("Target", value: target.pioEnv)
					.accessibilityElement(children: .combine)
				LabeledContent("Installed", value: target.firmwareVersion)
					.accessibilityElement(children: .combine)

				if let eventVersion = event.firmwareVersion, !eventVersion.isEmpty {
					LabeledContent("Event version", value: eventVersion)
						.accessibilityElement(children: .combine)
				}

				switch availability {
				case let .available(selection):
					LabeledContent("Install version", value: selection.artifact.version)
						.accessibilityElement(children: .combine)
					Label(
						selection.purpose == .event
							? "Signed event firmware is available for this exact device target."
							: "Signed standard firmware is available for this exact device target.",
						systemImage: "checkmark.shield.fill"
					)
					.foregroundStyle(.green)
					.font(.callout)
				case let .unavailable(reason):
					Label(unavailableMessage(for: reason), systemImage: "safari")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
			}

			Section {
				primaryAction

				if case let .failed(message) = preparationState {
					Label(message, systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.red)
						.font(.callout)
				}
			} footer: {
				Text(actionFooter)
			}
		}
		.navigationTitle(installPurpose == .event ? "Event Firmware" : "Standard Firmware")
		.navigationBarTitleDisplayMode(.inline)
		.sheet(item: $simulatorPreview) { preview in
			SimulatorEventFirmwareProgressView(preview: preview)
		}
		.onDisappear {
			preparationTask?.cancel()
			preparationTask = nil
		}
	}

	@ViewBuilder
	private var primaryAction: some View {
		switch EventFirmwareInstallerPolicy.primaryAction(for: availability) {
		case .install:
			Button {
				prepareVerifiedArtifact()
			} label: {
				HStack {
					Label(actionTitle, systemImage: actionIcon)
					Spacer()
					if preparationState == .preparing {
						ProgressView()
					}
				}
			}
			.disabled(preparationState == .preparing)
		case .webFlasher:
			Link(destination: webFlasherURL) {
				HStack {
					Label("Open Meshtastic Web Flasher", systemImage: "safari")
					Spacer()
					Image(systemName: "arrow.up.right")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	private var installPurpose: EventFirmwareOTAInstallPurpose {
		accessoryManager.firmwareEdition.editionKey == event.edition ? .standard : .event
	}

	private var availability: EventFirmwareOTAAvailability {
		EventFirmwareOTAAvailabilityResolver(
			contract: EventFirmwareOTAContractSource.currentContract
		).availability(
			edition: event.edition,
			target: target,
			purpose: installPurpose
		)
	}

	private var target: EventFirmwareOTATarget {
		let architecture = hardware.architecture ?? ""
		return EventFirmwareOTATarget(
			pioEnv: node.myInfo?.pioEnv ?? hardware.platformioTarget ?? "",
			hwModel: Int(node.user?.hwModelId ?? 0),
			architecture: architecture,
			firmwareVersion: node.metadata?.firmwareVersion
				?? "",
			supportsOTA: supportsInAppOTA(architecture: architecture),
			partitionScheme: hardware.partitionScheme,
			bootloaderVersion: nil
		)
	}

	private var actionTitle: String {
		installPurpose == .event ? "Install Event Firmware" : "Return to Standard Firmware"
	}

	private var actionIcon: String {
		installPurpose == .event ? "calendar.badge.checkmark" : "arrow.uturn.backward.circle"
	}

	private var actionFooter: String {
		switch availability {
		case .available:
			return "The download is verified before the existing firmware installer is opened. Keep the app open and your device nearby during installation."
		case .unavailable:
			return "This app cannot verify a compatible in-app package for this exact device. The web flasher provides the supported installation path."
		}
	}

	private var webFlasherURL: URL {
		URL(string: "https://flasher.meshtastic.org") ?? URL(fileURLWithPath: "/")
	}

	private func supportsInAppOTA(architecture: String) -> Bool {
		switch Architecture(rawValue: architecture) {
		case .esp32, .esp32C3, .esp32S3, .esp32C6:
			return true
		case .nrf52840, .rp2040, .none:
			return false
		}
	}

	private func unavailableMessage(
		for reason: EventFirmwareOTAUnavailableReason
	) -> String {
		switch reason {
		case .contractUnavailable:
			return "No trusted installation contract is currently published for this event."
		case .contractEditionMismatch:
			return "The published installation contract is for a different event."
		case .noCompatibleArtifact:
			return "No package is published for this exact device target."
		case let .sourceFirmwareTooOld(minimum):
			return "In-app installation requires device firmware \(minimum) or newer."
		case let .bootloaderTooOld(minimum):
			return "In-app installation requires bootloader \(minimum) or newer."
		case .unsupportedOTAPath:
			return "This device does not have an app-supported event firmware OTA path."
		case .untrustedArtifact:
			return "The available package does not meet the app's download trust policy."
		}
	}

	private func prepareVerifiedArtifact() {
		guard case let .available(selection) = availability else { return }
		let expectedNodeNum = node.num
		guard EventFirmwareInstallerPolicy.isExpectedDeviceActive(
			expectedNodeNum: expectedNodeNum,
			activeNodeNum: accessoryManager.activeDeviceNum
		) else {
			preparationState = .failed(
				"Reconnect to this device before preparing its firmware package."
			)
			return
		}
		preparationState = .preparing

		preparationTask?.cancel()
		preparationTask = Task {
			do {
				let localURL = try await downloader.prepare(selection.artifact)
				try Task.checkCancellation()
				await MainActor.run {
					guard EventFirmwareInstallerPolicy.isExpectedDeviceActive(
						expectedNodeNum: expectedNodeNum,
						activeNodeNum: accessoryManager.activeDeviceNum
					),
					EventFirmwareInstallerPolicy.isPreparedSelectionCurrent(
						selection,
						availability: availability
					) else {
						preparationState = .failed(
							"The connected device changed. Select the event again for the current device."
						)
						preparationTask = nil
						return
					}
					preparationState = .idle
					#if DEBUG && targetEnvironment(simulator)
					simulatorPreview = SimulatorFirmwarePreview(
						title: actionTitle,
						fileName: localURL.lastPathComponent,
						byteCount: selection.artifact.byteCount
					)
					#else
					onInstall(selection.artifact.format.firmwareType, localURL)
					#endif
					preparationTask = nil
				}
			} catch is CancellationError {
				await MainActor.run {
					preparationState = .idle
					preparationTask = nil
				}
			} catch {
				await MainActor.run {
					preparationState = .failed(
						"The firmware package could not be downloaded and verified."
					)
					preparationTask = nil
				}
			}
		}
	}
}

private enum EventFirmwareInstallerDependencies {
	static func downloader() -> EventFirmwareArtifactDownloader {
		#if DEBUG && targetEnvironment(simulator)
		return EventFirmwareArtifactDownloader(
			cacheDirectory: FileManager.default.temporaryDirectory
				.appendingPathComponent("EventFirmwareSimulator", isDirectory: true),
			download: { url, _ in
				guard let payload = EventFirmwareOTADebugFixture.payload(for: url) else {
					throw URLError(.fileDoesNotExist)
				}
				let temporaryURL = FileManager.default.temporaryDirectory
					.appendingPathComponent(UUID().uuidString)
				try payload.write(to: temporaryURL, options: .atomic)
				return (
					temporaryURL,
					URLResponse(
						url: url,
						mimeType: "application/octet-stream",
						expectedContentLength: payload.count,
						textEncodingName: nil
					)
				)
			}
		)
		#else
		return EventFirmwareArtifactDownloader()
		#endif
	}
}

private extension EventFirmwareOTAArtifact.Format {
	var firmwareType: FirmwareFile.FirmwareType {
		switch self {
		case .bin:
			return .bin
		case .otaZip:
			return .otaZip
		}
	}
}

private struct SimulatorFirmwarePreview: Identifiable {
	let id = UUID()
	let title: String
	let fileName: String
	let byteCount: Int64
}

private struct SimulatorEventFirmwareProgressView: View {
	let preview: SimulatorFirmwarePreview

	@Environment(\.dismiss) private var dismiss
	@State private var progress = 0.0
	@State private var isComplete = false

	var body: some View {
		NavigationStack {
			VStack(spacing: 24) {
				Spacer()

				if isComplete {
					Image(systemName: "checkmark.circle.fill")
						.font(.system(size: 52))
						.foregroundStyle(.green)
				} else {
					ProgressView()
						.controlSize(.large)
						.scaleEffect(1.4)
				}

				VStack(spacing: 8) {
					Text(isComplete ? "Mock Install Complete" : preview.title)
						.font(.title2.bold())
					Text("Simulator Preview")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.secondary)
				}

				ProgressView(value: progress)
					.progressViewStyle(.linear)
					.padding(.horizontal, 32)

				VStack(spacing: 4) {
					Text(preview.fileName)
						.font(.footnote.monospaced())
					Text(ByteCountFormatter.string(fromByteCount: preview.byteCount, countStyle: .file))
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Spacer()

				if isComplete {
					Button("Done") {
						dismiss()
					}
					.buttonStyle(.borderedProminent)
					.controlSize(.large)
				} else {
					Text("No radio is contacted in this simulator preview.")
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}
			.padding()
			.navigationTitle("Firmware Install")
			.navigationBarTitleDisplayMode(.inline)
			.interactiveDismissDisabled(!isComplete)
			.task {
				for step in 1...40 {
					guard !Task.isCancelled else { return }
					try? await Task.sleep(for: .milliseconds(75))
					progress = Double(step) / 40
				}
				isComplete = true
			}
		}
	}
}
