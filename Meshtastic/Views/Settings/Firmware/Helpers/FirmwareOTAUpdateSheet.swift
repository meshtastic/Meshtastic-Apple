//
//  FirmwareOTAUpdateSheet.swift
//  Meshtastic
//
//  Created by Antigravity on 8/15/26.
//

import SwiftUI

/// Metadata row item displayed in the OTA confirmation section.
struct OTAMetadataItem: Identifiable, Hashable {
	var id: String { label }
	let label: String
	let value: String
	var isMonospaced: Bool = false

	init(label: String, value: String, isMonospaced: Bool = false) {
		self.label = label
		self.value = value
		self.isMonospaced = isMonospaced
	}
}

/// Curated rotating tips and educational insights displayed during firmware updates.
enum FirmwareUpdateTips {
	static let messages: [String] = [
		String(localized: "Keep your device close to your phone during the update.", comment: "OTA update tip: keep device close"),
		String(localized: "Do not close the app or turn off Bluetooth while the update is in progress.", comment: "OTA update tip: do not close app"),
		String(localized: "You can safely play Chirpy Hop while waiting for the update to complete.", comment: "OTA update tip: safe to play game"),
		String(localized: "Visit meshtastic.org/docs for guides, hardware information, and community tips.", comment: "OTA update tip: docs website")
	]
}

/// Unified, reusable OTA Firmware Update Sheet for BLE, Wi-Fi, and simulated updates.
struct FirmwareOTAUpdateSheet: View {
	let title: String
	var metadata: [OTAMetadataItem] = []
	var headerNote: String = String(localized: "Please do not leave this screen until the update is complete. You can safely play Chirpy Hop while waiting!", comment: "Notice displayed during OTA firmware update")

	let progress: Double
	let statusState: LocalOTAStatusCode
	let statusMessage: String

	let inRetryWorkflow: Bool
	let isStartDisabled: Bool
	var startButtonTitle: String?

	let onStart: () -> Void
	let onRetry: () -> Void
	let onDismiss: () -> Void

	var gameTitle: String?

	@State private var showChirpyGame = false
	@State private var showStopConfirmation = false
	@State private var tipIndex: Int = 0
	private let tipTimer = Timer.publish(every: 8.0, on: .main, in: .common).autoconnect()

	var body: some View {
		NavigationStack {
			GeometryReader { geometry in
				ScrollView {
					VStack(spacing: 20) {
						Spacer()

					if !headerNote.isEmpty {
						Text(headerNote)
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
							.fixedSize(horizontal: false, vertical: true)
							.padding(.horizontal, 24)
					}

					if !metadata.isEmpty {
						VStack(spacing: 8) {
							ForEach(metadata) { item in
								HStack {
									Text(item.label)
										.font(.caption)
										.foregroundStyle(.secondary)
									Spacer()
									Text(item.value)
										.font(item.isMonospaced ? .caption.monospaced() : .caption)
										.textSelection(.enabled)
										.lineLimit(2)
								}
							}
						}
						.padding(12)
						.background(Color(UIColor.secondarySystemBackground))
						.clipShape(RoundedRectangle(cornerRadius: 12))
						.padding(.horizontal, 24)
					}

					CircularProgressView(
						progress: progress,
						isIndeterminate: (statusState == .preparing),
						isError: (statusState == .error),
						size: 225.0,
						subtitleText: (statusState == .error) ? nil : statusState.rawValue
					)
					.frame(minHeight: 245.0)

					VStack(spacing: 14) {
						if statusState != .idle {
							Text(statusMessage.isEmpty ? statusState.rawValue : statusMessage)
								.frame(maxWidth: .infinity)
								.multilineTextAlignment(.center)
								.font(.headline)
								.foregroundStyle(statusState == .error ? .red : .primary)
								.fixedSize(horizontal: false, vertical: true)
								.padding(.horizontal, 24)
						}

						switch statusState {
						case .idle:
							Button {
								onStart()
							} label: {
								if let customTitle = startButtonTitle {
									Text(customTitle)
										.frame(maxWidth: .infinity)
								} else if inRetryWorkflow {
									Label("Retry Update", systemImage: "arrow.clockwise")
										.frame(maxWidth: .infinity)
								} else {
									Label("Reboot & Start Update", systemImage: "square.and.arrow.down")
										.frame(maxWidth: .infinity)
								}
							}
							.buttonStyle(.borderedProminent)
							.controlSize(.large)
							.disabled(isStartDisabled)
							.padding(.horizontal, 24)

						case .error:
							Button {
								onRetry()
							} label: {
								Label("Retry", systemImage: "arrow.clockwise")
									.frame(maxWidth: .infinity)
									.foregroundStyle(.white)
							}
							.buttonStyle(.borderedProminent)
							.tint(.red)
							.controlSize(.large)
							.padding(.horizontal, 24)

						default:
							EmptyView()
						}

						if statusState.gamePhase.isActive {
							FirmwareUpdateGameButton(isPresented: $showChirpyGame, status: gameStatus)
								.padding(.horizontal, 24)
						}

						if statusState == .transferring || statusState == .preparing || statusState == .waitingForConnection || statusState == .connected {
							Text(FirmwareUpdateTips.messages[tipIndex % FirmwareUpdateTips.messages.count])
								.font(.footnote)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
								.fixedSize(horizontal: false, vertical: true)
								.padding(.horizontal, 28)
								.padding(.top, 4)
								.transition(.opacity)
								.id(tipIndex)
						}
					}
					.frame(maxWidth: .infinity)

					Spacer()
				}
				.frame(minHeight: geometry.size.height)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 12)
			}
		}
		.navigationTitle(title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button {
						// Always a way out. An update can stall somewhere the app cannot
						// recover from — the radio never advertises in OTA mode, say — and
						// a disabled close button leaves force-quitting as the only exit.
						if isDismissSafe {
							onDismiss()
						} else {
							showStopConfirmation = true
						}
					} label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel(String(localized: "Close", comment: "VoiceOver: dismiss this sheet"))
				}
			}
		}
		.interactiveDismissDisabled(true)
		.confirmationDialog(
			Text("Stop the update?", comment: "Title of the confirmation shown when closing an update in progress"),
			isPresented: $showStopConfirmation,
			titleVisibility: .visible
		) {
			Button(role: .destructive) {
				onDismiss()
			} label: {
				Text("Stop Update", comment: "Button that abandons an update in progress")
			}
			Button(role: .cancel) { } label: {
				Text("Keep Waiting", comment: "Button that returns to an update in progress")
			}
		} message: {
			Text("The device stays in update mode until the update finishes or you power it off and on again.",
				 comment: "Explains what happens to the device when an update is abandoned")
		}
		.firmwareUpdateGame(isPresented: $showChirpyGame, status: gameStatus)
		.onReceive(tipTimer) { _ in
			withAnimation(.easeInOut(duration: 0.35)) {
				tipIndex = (tipIndex + 1) % FirmwareUpdateTips.messages.count
			}
		}
	}

	/// States where nothing is under way, so closing needs no confirmation.
	private var isDismissSafe: Bool {
		[.idle, .completed, .error].contains(statusState)
	}

	private var gameStatus: FirmwareUpdateGameStatus {
		FirmwareUpdateGameStatus(
			title: gameTitle ?? title,
			message: statusMessage.isEmpty ? statusState.rawValue : statusMessage,
			progress: progress,
			phase: statusState.gamePhase
		)
	}
}

// MARK: - OTA Simulator & Previews

#if DEBUG
/// Transport mode preset for the OTA Simulator.
enum OTASimulatorPreset: String, CaseIterable, Identifiable {
	case ble = "ESP32 BLE"
	case wifi = "ESP32 Wi-Fi"
	case custom = "Custom / NRF"

	var id: String { rawValue }

	var title: String {
		switch self {
		case .ble: return "ESP32 BLE Updater"
		case .wifi: return "ESP32 WiFi Updater"
		case .custom: return "OTA Firmware Updater"
		}
	}

	var gameTitle: String {
		switch self {
		case .ble: return "ESP32 BLE OTA"
		case .wifi: return "ESP32 Wi-Fi OTA"
		case .custom: return "Firmware OTA"
		}
	}
}

/// Interactive simulator view embedded with FirmwareOTAUpdateSheet.
struct FirmwareOTASimulatorView: View {
	@Environment(\.dismiss) private var dismiss

	@State private var selectedPreset: OTASimulatorPreset = .ble
	@State private var progress: Double = 0.0
	@State private var statusState: LocalOTAStatusCode = .idle
	@State private var statusMessage: String = "Ready"
	@State private var inRetryWorkflow: Bool = false
	@State private var simulateFailure: Bool = false
	@State private var isLiveSimulating: Bool = false

	@State private var showControlDrawer: Bool = false

	var body: some View {
		VStack(spacing: 0) {
			#if DEBUG
			simulatorControlBar
			#endif

			FirmwareOTAUpdateSheet(
				title: selectedPreset.title,
				progress: progress,
				statusState: statusState,
				statusMessage: statusMessage,
				inRetryWorkflow: inRetryWorkflow,
				isStartDisabled: false,
				onStart: {
					startSimulatedUpdate()
				},
				onRetry: {
					inRetryWorkflow = true
					resetToIdle()
				},
				onDismiss: {
					// The simulation runs in an unstructured Task that would otherwise keep
					// going after "Stop Update".
					isLiveSimulating = false
					dismiss()
				},
				gameTitle: selectedPreset.gameTitle
			)
		}
		.sheet(isPresented: $showControlDrawer) {
			simulatorInspectorSheet
		}
	}

	// MARK: - Subviews

	private var simulatorControlBar: some View {
		HStack {
			Picker("Preset", selection: $selectedPreset) {
				ForEach(OTASimulatorPreset.allCases) { preset in
					Text(preset.rawValue).tag(preset)
				}
			}
			.pickerStyle(.segmented)

			Button {
				showControlDrawer = true
			} label: {
				Image(systemName: "slider.horizontal.3")
			}
			.accessibilityLabel("Open Simulator Controls")
		}
		.padding(.horizontal)
		.padding(.vertical, 6)
		.background(Color(uiColor: .secondarySystemBackground))
	}

	private var simulatorInspectorSheet: some View {
		NavigationStack {
			Form {
				Section("State Control") {
					Picker("Status State", selection: $statusState) {
						Text("Idle").tag(LocalOTAStatusCode.idle)
						Text("Waiting").tag(LocalOTAStatusCode.waitingForConnection)
						Text("Connected").tag(LocalOTAStatusCode.connected)
						Text("Preparing").tag(LocalOTAStatusCode.preparing)
						Text("Transferring").tag(LocalOTAStatusCode.transferring)
						Text("Completed").tag(LocalOTAStatusCode.completed)
						Text("Error").tag(LocalOTAStatusCode.error)
					}

					VStack(alignment: .leading) {
						Text("Progress: \(Int(progress * 100))%")
						Slider(value: $progress, in: 0.0...1.0)
					}

					TextField("Status Message", text: $statusMessage)

					Toggle("Simulate Failure Mid-way", isOn: $simulateFailure)
					Toggle("In Retry Workflow", isOn: $inRetryWorkflow)
				}

				Section("Actions") {
					Button("Run Live Animation Cycle") {
						showControlDrawer = false
						startSimulatedUpdate()
					}

					Button("Reset to Idle", role: .destructive) {
						resetToIdle()
					}
				}
			}
			.navigationTitle("OTA Inspector")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						showControlDrawer = false
					}
				}
			}
		}
	}

	// MARK: - Simulation Logic

	private func resetToIdle() {
		isLiveSimulating = false
		progress = 0.0
		statusState = .idle
		statusMessage = "Ready to start"
	}

	private func startSimulatedUpdate() {
		isLiveSimulating = true
		progress = 0.0
		statusState = .waitingForConnection
		statusMessage = "Connecting to device..."

		Task {
			// Phase 1: Connecting
			try? await Task.sleep(for: .milliseconds(600))
			guard isLiveSimulating else { return }
			statusState = .connected
			statusMessage = "Connected. Initializing..."

			// Phase 2: Preparing / Erasing
			try? await Task.sleep(for: .milliseconds(700))
			guard isLiveSimulating else { return }
			statusState = .preparing
			statusMessage = "Erasing partition..."

			// Phase 3: Transferring
			try? await Task.sleep(for: .milliseconds(900))
			guard isLiveSimulating else { return }
			statusState = .transferring
			statusMessage = "Uploading firmware..."

			let steps = 40
			for step in 1...steps {
				try? await Task.sleep(for: .milliseconds(80))
				guard isLiveSimulating else { return }
				progress = Double(step) / Double(steps)

				if simulateFailure && step == 20 {
					statusState = .error
					statusMessage = "Error: Connection timed out during packet transfer."
					isLiveSimulating = false
					return
				}
			}

			// Phase 4: Final verification and complete
			statusMessage = "Verifying hash..."
			try? await Task.sleep(for: .milliseconds(500))
			guard isLiveSimulating else { return }

			progress = 1.0
			statusState = .completed
			statusMessage = "Success! Device rebooting..."
			isLiveSimulating = false
		}
	}
}

// MARK: - Previews

#Preview("OTA Simulator - Interactive") {
	FirmwareOTASimulatorView()
}

#Preview("OTA BLE - Uploading State") {
	FirmwareOTAUpdateSheet(
		title: "ESP32 BLE Updater",
		progress: 0.65,
		statusState: .transferring,
		statusMessage: "Uploading firmware...",
		inRetryWorkflow: false,
		isStartDisabled: false,
		onStart: {},
		onRetry: {},
		onDismiss: {},
		gameTitle: "ESP32 BLE OTA"
	)
}

#Preview("OTA WiFi - Error State") {
	FirmwareOTAUpdateSheet(
		title: "ESP32 WiFi Updater",
		progress: 0.35,
		statusState: .error,
		statusMessage: "Failed to establish connection: Connection timed out",
		inRetryWorkflow: false,
		isStartDisabled: false,
		onStart: {},
		onRetry: {},
		onDismiss: {},
		gameTitle: "ESP32 Wi-Fi OTA"
	)
}
#endif

