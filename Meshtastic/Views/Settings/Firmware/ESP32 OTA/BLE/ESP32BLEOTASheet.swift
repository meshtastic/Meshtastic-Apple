//
//  ESP32BLEOTASheet.swift
//  Meshtastic
//
//  Created by jake on 12/20/25.
//

import SwiftUI
import os
import CoreBluetooth
import CryptoKit

struct ESP32BLEOTASheet: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.modelContext) var context
	@StateObject var ota = ESP32BLEOTAViewModel()
	
	@State var rebootSuccessful = false
	@State var inRetryWorkflow = false
	@State private var showChirpyGame = false
	
	// The stuff we're updating, and the place we're updating it to
	let binFileURL: URL

	// To dismiss the intro sheet when complete.
	var onUpdateComplete: (() -> Void)?

	@State var peripheral: CBPeripheral?
	
	var body: some View {
		NavigationStack {
			List {
				Section {
					VStack(alignment: .leading) {
						Text("Firmware File").font(.caption).foregroundColor(.secondary)
						Text("\(self.binFileURL.lastPathComponent)").font(.caption)
					}
					VStack(alignment: .leading) {
						Text("BLE Device").font(.caption).foregroundColor(.secondary)
						if let peripheral {
							Text("\(peripheral.name ?? "Unknown")").font(.caption)
							Text("\(peripheral.identifier.uuidString)").font(.caption)
						} else {
							Text("No device connected. Will use first discovered device.").font(.caption)
						}
					}
				} header: {
					Text("Please do not leave this screen until this process is complete.")
						.multilineTextAlignment(.center)
				} footer: {
					Text("Please be sure this is correct before proceeding.")
				}
				
				Section {
					HStack(alignment: .center) {
						Spacer()
						
						// MARK: - Progress View
						CircularProgressView(
							progress: ota.transferProgress,
							isIndeterminate: (ota.otaStatus == .preparing),
							isError: (ota.otaStatus == .error),
							size: 225.0,
							// If error, show nil (triangle only). Text is shown below.
							subtitleText: (ota.otaStatus == .error) ? nil : ota.otaStatus.rawValue
						)
						.frame(minHeight: 250.0)
						
						Spacer()
					}
					.listRowBackground(Color.clear)
					
					VStack(spacing: 12) {
						if ota.otaStatus != .idle {
							Text(ota.statusMessage)
								.frame(maxWidth: .infinity)
								.multilineTextAlignment(.center)
								.font(.headline)
								.foregroundStyle(ota.otaStatus == .error ? .red : .primary)
						}
						
						switch ota.otaStatus {
						case .idle:
							beginBLEProcessButton()
							
						case .error:
							retryButton()
							
						default:
							EmptyView()
						}
					}
					.listRowBackground(Color.clear)
				}
				.listRowSeparator(.hidden)

				if ota.otaStatus.gamePhase.isActive {
					Section {
						FirmwareUpdateGameButton(isPresented: $showChirpyGame, status: gameStatus)
					}
					.textCase(nil)
				}
			}
			.listSectionSpacing(.compact)
			.navigationTitle("ESP32 BLE Updater")
			.navigationBarTitleDisplayMode(.inline)

		}
		.overlay(alignment: .topLeading) {
			Button {
				if let onUpdateComplete, ota.otaStatus == .completed {
					onUpdateComplete()
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
			.disabled(![.idle, .completed, .error].contains(ota.otaStatus))
			.opacity(![.idle, .completed, .error].contains(ota.otaStatus) ? 0.3 : 1.0)
		}
		.task {
			// Attempt to grab peripheral from current BLE connection
			if let connection = accessoryManager.activeConnection?.connection as? BLEConnection {
				self.peripheral = await connection.peripheral
			}
		}
		.interactiveDismissDisabled(true)
		.textCase(nil)
		.firmwareUpdateGame(isPresented: $showChirpyGame, status: gameStatus)
	}
	
	// MARK: - Component Views

	private var gameStatus: FirmwareUpdateGameStatus {
		FirmwareUpdateGameStatus(
			title: "ESP32 BLE OTA",
			message: ota.statusMessage.isEmpty ? ota.otaStatus.rawValue : ota.statusMessage,
			progress: ota.transferProgress,
			phase: ota.otaStatus.gamePhase
		)
	}
	
	@ViewBuilder
	func retryButton() -> some View {
		Button {
			self.inRetryWorkflow = true
			var transaction = Transaction(animation: .none)
			transaction.disablesAnimations = true
			
			withTransaction(transaction) {
				// Determine if we need to reboot again (usually no, unless connection was totally lost before reboot)
				ota.retry()
			}
		} label: {
			Label("Retry", systemImage: "arrow.clockwise")
				.frame(maxWidth: .infinity)
				.foregroundStyle(.white)
		}
		.buttonStyle(.borderedProminent)
		.tint(.red)
		.controlSize(.large)
	}
	
	@ViewBuilder
	func beginBLEProcessButton() -> some View {
		Button {
			startBLEProcess()
		} label: {
			if self.inRetryWorkflow {
				Label("Retry Update", systemImage: "arrow.clockwise")
					.frame(maxWidth: .infinity)
			} else {
				Label("Reboot & Start Update", systemImage: "square.and.arrow.down")
					.frame(maxWidth: .infinity)
			}
		}
		.buttonStyle(.bordered)
		.controlSize(.large)
		.disabled(accessoryManager.activeDeviceNum == nil)
	}
	
	// MARK: - Logic
	
	private func startBLEProcess() {
		// Safe unwrap of required data
		guard let deviceNum = accessoryManager.activeDeviceNum,
			  let connectedNode = getNodeInfo(id: deviceNum, context: context),
			  let user = connectedNode.user else {
			return
		}
		
		Task {
			do {
				if !rebootSuccessful {
					// 1. Move file reading/hashing to a detached task to avoid blocking Main Thread
					let sha256Digest = try await Task.detached(priority: .userInitiated) {
						let data = try Data(contentsOf: binFileURL)
						let digest = SHA256.hash(data: data)
						return Data(digest)
					}.value
					
					// 2. Send the reboot command via existing connection
					try await accessoryManager.sendRebootOta(fromUser: user, toUser: user, mode: .otaBle, otaHash: sha256Digest)
					rebootSuccessful = true
					
					// Give some time for any final incomming notifications
					try await Task.sleep(for: .seconds(1.0))

					// 3. Disconnect app so the ViewModel can grab the new OTA-Mode advertisement
					try await accessoryManager.disconnect()
					
					// 4. Disable discovery to focus on the specific OTA device
					accessoryManager.otaInProgress = true
					accessoryManager.stopDiscovery()
					
					// 5. Wait briefly for device to reboot
					try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
				}
				
				// 6. Set auto-reconnect preference
				accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = true
				
				// 7. Start the OTA process
				await ota.startOTA(binURL: binFileURL, desiredPeripheral: peripheral?.identifier)
				
				// 8. Cleanup / Restart discovery
				accessoryManager.otaInProgress = false
				accessoryManager.startDiscovery()
				
			} catch {
				Logger.mesh.error("ESP32 BLE OTA Failed: \(error.localizedDescription)")
				// Note: You might want to update `ota.otaStatus` to .error here if the View Model doesn't catch it
			}
		}
	}
}
