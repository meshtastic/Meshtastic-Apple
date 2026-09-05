//
//  NRFDFUSheet.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/11/25.
//

import SwiftUI
import OSLog

struct NRFDFUSheet: View {
	@Environment(\.dismiss) var dismiss
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State var showWarningAlert = true
	@StateObject private var dfuViewModel = DFUViewModel()
	@State private var showChirpyGame = false
	@State private var showStopConfirmation = false
	
	let firmwareToFlash: URL
	
	var body: some View {
		VStack {
			if showWarningAlert {
				UpdateWarningSheet(
					onDismiss: { dismiss() },
					onAccept: { showWarningAlert = false }
				)
			} else {
				GeometryReader { geometry in
					ScrollView {
						VStack(spacing: 20.0) {
							Spacer()

							VStack(spacing: 4) {
								Text("Nordic DFU Update")
									.font(.title2.bold())

								Text("DFU Firmware Update")
									.font(.subheadline)
									.foregroundStyle(.secondary)
							}
							.padding(.top, 8)

							Text("Please do not leave this screen until the update is complete. You can safely play Chirpy Hop while waiting!")
								.font(.caption)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
								.padding(.horizontal)

							CircularProgressView(
								progress: dfuViewModel.progress,
								isIndeterminate: (self.dfuViewModel.state == .starting),
								isError: dfuViewModel.state.isError,
								size: 210.0,
								subtitleText: dfuViewModel.state.isError ? nil : dfuViewModel.statusMessage
							)
							.frame(minHeight: 230.0)

							VStack(spacing: 12) {
								switch dfuViewModel.state {
								case .idle:
									Button("Begin Update") {
										Task {
											guard let connection = accessoryManager.activeConnection?.connection as? BLEConnection else {
												Logger.services.error("NRF DFU: no active BLE connection, cannot start")
												return
											}
											let peripheral = await connection.peripheral
											// The DFU library reboots the radio into the bootloader and
											// reconnects to it on its own. Stop scanning and auto-connect
											// first or the app grabs the device out from under it.
											accessoryManager.otaInProgress = true
											accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = false
											accessoryManager.stopDiscovery()
											Logger.services.info("NRF DFU: handing the radio to the DFU library")
											dfuViewModel.startDFU(peripheral: peripheral, zipFileUrl: firmwareToFlash)
										}
									}
									.controlSize(.large)
									.frame(maxWidth: .infinity, minHeight: 48)
									.clipShape(RoundedRectangle(cornerRadius: 10))
									.buttonStyle(.borderedProminent)

								case .uploading, .starting, .success:
									Text(dfuViewModel.rotatingMessage)
										.font(.headline)
										.multilineTextAlignment(.center)
										.padding(.horizontal)
								case .error(let message):
									Text("Error: \(message)")
										.font(.headline)
										.foregroundStyle(.red)
										.multilineTextAlignment(.center)
										.padding(.horizontal)
								}
							}
							.frame(maxWidth: .infinity)
							.padding(.horizontal)

							if dfuViewModel.state.gamePhase.isActive {
								FirmwareUpdateGameButton(isPresented: $showChirpyGame, status: gameStatus)
									.padding(.horizontal)
									.padding(.top, 4)
							}

							Spacer()
						}
						.frame(minHeight: geometry.size.height)
						.frame(maxWidth: .infinity)
						.padding(.bottom, 24)
					}
				}
			}
		}
		.overlay(alignment: .topLeading) {
			Button {
				// Always a way out. An update can stall somewhere the app cannot recover
				// from, and a disabled close button leaves force-quitting as the only exit.
				if [.starting, .uploading].contains(dfuViewModel.state) {
					showStopConfirmation = true
				} else {
					dismiss()
				}
			} label: {
				Image(systemName: "xmark.circle.fill")
					.font(.title)
					.symbolRenderingMode(.palette)
					.foregroundStyle(.white, Color(.systemGray3))
			}
			.accessibilityLabel(String(localized: "Close", comment: "VoiceOver: dismiss this sheet"))
			.buttonStyle(.plain)
			.padding()
		}
		.interactiveDismissDisabled(true)
		.confirmationDialog(
			Text("Stop the update?", comment: "Title of the confirmation shown when closing an update in progress"),
			isPresented: $showStopConfirmation,
			titleVisibility: .visible
		) {
			Button(role: .destructive) {
				Task { await stopUpdate() }
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
		.onDisappear {
			if accessoryManager.otaInProgress {
				restoreDiscovery()
			}
		}
	}

	/// Abort, then wait for the library to confirm before handing the radio back: restarting
	/// discovery while NordicDFU still owns the peripheral lets auto-connect grab it out from
	/// under the abort. Bounded, because an abort that never confirms must not leave the app
	/// unable to find the radio again.
	private func stopUpdate() async {
		dfuViewModel.abort()
		let deadline = Date().addingTimeInterval(3)
		while !dfuViewModel.didAbort && Date() < deadline {
			try? await Task.sleep(for: .milliseconds(100))
		}
		if !dfuViewModel.didAbort {
			Logger.services.error("NRF DFU: abort was not confirmed, handing the radio back anyway")
		}
		if accessoryManager.otaInProgress {
			restoreDiscovery()
		}
		dismiss()
	}

	/// Give the radio back to the app once DFU is finished: restart discovery and
	/// let auto-connect pick the device up when it reboots into the new firmware.
	private func restoreDiscovery() {
		Logger.services.info("NRF DFU: restoring discovery")
		accessoryManager.otaInProgress = false
		accessoryManager.userRequestedConnectionCancellation = false
		accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = true
		accessoryManager.startDiscovery()
	}

	private var gameStatus: FirmwareUpdateGameStatus {
		FirmwareUpdateGameStatus(
			title: "nRF DFU",
			message: dfuViewModel.statusMessage,
			progress: dfuViewModel.progress,
			phase: dfuViewModel.state.gamePhase
		)
	}
}

private struct UpdateWarningSheet: View {
	let onDismiss: () -> Void
	let onAccept: () -> Void

	var body: some View {
		VStack(spacing: 16) {
			Text("Update Warning")
				.font(.title.bold())
				.multilineTextAlignment(.center)
				.padding(.top, 24)

			Text("You are about to flash new firmware to your device. This process carries risks. Unsuccessful updates may fail and in some cases require re-flashing the bootloader.")
				.font(.callout)
				.fixedSize(horizontal: false, vertical: true)
				.multilineTextAlignment(.center)
				.padding(.horizontal)

			VStack(alignment: .leading, spacing: 6) {
				Label("Ensure your device is charged.", systemImage: "battery.75percent")
				Label("Connect your device to a stable power supply.", systemImage: "powerplug.fill")
				Label("Keep the device close to your phone.", systemImage: "antenna.radiowaves.left.and.right")
				Label("Do not close the app during the update.", systemImage: "xmark.app")
				Label("Verify you have selected the correct firmware.", systemImage: "checkmark.shield")
			}
			.font(.caption)
			.fixedSize(horizontal: false, vertical: true)
			.foregroundStyle(.secondary)
			.padding(.horizontal)

			Text("Note: This will temporarily disconnect your device during the update.")
				.font(.caption)
				.fixedSize(horizontal: false, vertical: true)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.padding(.horizontal)

			Spacer()

			VStack(spacing: 10) {
				Button(role: .destructive) {
					onAccept()
				} label: {
					Text("I Know What I\'m Doing")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.tint(.red)
				.controlSize(.large)

				Button {
					onDismiss()
				} label: {
					Text("Not Now")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
				.controlSize(.large)
			}
			.padding(.horizontal)
			.padding(.bottom, 24)
		}
		.padding(.top)
	}
}

#Preview {
	NRFDFUSheet(firmwareToFlash: URL(fileURLWithPath: "/tmp/firmware-nrf52840.zip"))
		.environmentObject(AccessoryManager.shared)
}
