//
//  FirmwareOTAUpdateSheet.swift
//  Meshtastic
//
//  Created by Antigravity on 8/15/26.
//

import SwiftUI

/// The ESP32 updaters' (and the simulator's) entry onto the shared update screen: maps the
/// ESP32 status codes onto its stages.
struct FirmwareOTAUpdateSheet: View {
	let progress: Double
	let statusState: LocalOTAStatusCode
	let statusMessage: String
	let isStartDisabled: Bool

	let onStart: () -> Void
	let onRetry: () -> Void
	let onDismiss: () -> Void

	var body: some View {
		FirmwareUpdateView(
			stage: FirmwareUpdateStage(statusState),
			progress: progress,
			detail: statusMessage,
			isStartDisabled: isStartDisabled,
			onStart: onStart,
			onRetry: onRetry,
			onDismiss: onDismiss
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
	@State private var simulateFailure: Bool = false
	@State private var isLiveSimulating: Bool = false

	@State private var showControlDrawer: Bool = false

	var body: some View {
		VStack(spacing: 0) {
			#if DEBUG
			simulatorControlBar
			#endif

			FirmwareOTAUpdateSheet(
				progress: progress,
				statusState: statusState,
				statusMessage: statusMessage,
				isStartDisabled: false,
				onStart: {
					startSimulatedUpdate()
				},
				onRetry: {
					resetToIdle()
				},
				onDismiss: {
					// The simulation runs in an unstructured Task that would otherwise keep
					// going after "Stop Update".
					isLiveSimulating = false
					dismiss()
				}
			)
		}
		.hostedSheet(isPresented: $showControlDrawer) {
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
		SheetNavigationStack {
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
		progress: 0.65,
		statusState: .transferring,
		statusMessage: "Uploading firmware...",
		isStartDisabled: false,
		onStart: {},
		onRetry: {},
		onDismiss: {}
	)
}

#Preview("OTA WiFi - Error State") {
	FirmwareOTAUpdateSheet(
		progress: 0.35,
		statusState: .error,
		statusMessage: "Failed to establish connection: Connection timed out",
		isStartDisabled: false,
		onStart: {},
		onRetry: {},
		onDismiss: {}
	)
}
#endif
