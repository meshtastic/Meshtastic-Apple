//
//  NRFDFUSheet.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/11/25.
//

import SwiftUI

struct NRFDFUSheet: View {
	@Environment(\.dismiss) var dismiss
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State var showWarningAlert = true
	@StateObject private var dfuViewModel = DFUViewModel()
	@State private var showChirpyGame = false
	
	let firmwareToFlash: URL
	
	var body: some View {
		VStack {
			if showWarningAlert {
				UpdateWarningSheet(
					onDismiss: { dismiss() },
					onAccept: { showWarningAlert = false }
				)
			} else {
				VStack(spacing: 20.0) {
					Text("Nordic DFU Update")
						.font(.title2.bold())

					Text("DFU Firmware Update")
						.font(.headline)

					Text("Please do not leave this screen until this process is complete.")
						.multilineTextAlignment(.center)
						.padding()

					CircularProgressView(progress: dfuViewModel.progress, isIndeterminate: (self.dfuViewModel.state == .starting), size: 225.0, subtitleText: dfuViewModel.statusMessage)

					Group {
						switch dfuViewModel.state {
						case .idle:
							Button("Begin Update") {
								Task {
									if let connection = accessoryManager.activeConnection?.connection as? BLEConnection {
										let peripheral = await connection.peripheral
										dfuViewModel.startDFU(peripheral: peripheral, zipFileUrl: firmwareToFlash)
									}
								}
							}
							.controlSize(.large)
							.frame(maxWidth: .infinity)
							.cornerRadius(10)
							.buttonStyle(.borderedProminent)

						case .uploading, .starting, .success:
							Text(dfuViewModel.rotatingMessage)
								.multilineTextAlignment(.center)
								.padding(.horizontal)
						case .error(let message):
							Text("Error: \(message)")
						}
					}.frame(minHeight: 250.0)

					if dfuViewModel.state.gamePhase.isActive {
						FirmwareUpdateGameButton(isPresented: $showChirpyGame, status: gameStatus)
							.padding(.horizontal)
							.padding(.bottom)
					}
				}
			}
		}
		.overlay(alignment: .topLeading) {
			Button {
				dismiss()
			} label: {
				Image(systemName: "xmark.circle.fill")
					.font(.title)
					.symbolRenderingMode(.palette)
					.foregroundStyle(.white, Color(.systemGray3))
			}
			.accessibilityLabel(String(localized: "Close", comment: "VoiceOver: dismiss this sheet"))
			.buttonStyle(.plain)
			.padding()
			.disabled([.starting, .uploading].contains(dfuViewModel.state))
			.opacity([.starting, .uploading].contains(dfuViewModel.state) ? 0.3 : 1.0)
		}
		.interactiveDismissDisabled(true)
		.firmwareUpdateGame(isPresented: $showChirpyGame, status: gameStatus)
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
