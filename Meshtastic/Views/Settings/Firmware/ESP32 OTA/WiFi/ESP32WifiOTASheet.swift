//
//  ESP32WifiOTASheet.swift
//  Meshtastic
//
//  Created by jake on 12/20/25.
//

import SwiftUI
import os
import CryptoKit

struct ESP32WifiOTASheet: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.modelContext) var context
	@StateObject var ota = ESP32WifiOTAViewModel()
	
	// The file we're updating, and the place we're updating it to
	let binFileURL: URL
	
	// IP address of the host (optional)
	@State var host: String?
	
	// To dismiss the intro sheet when complete.
	let onUpdateComplete: (() -> Void)?
	
	@State var alreadyRebooted: Bool = false
	@State var inRetryWorkflow = false
	/// Retained so dismissing the sheet cancels it. Without this the flow could resume after
	/// cleanup had already handed the radio back and start a transfer against a reconnected node.
	@State private var otaTask: Task<Void, Never>?

	init(binFileURL: URL, host: String? = nil, onUpdateComplete: (() -> Void)? = nil) {
		self.onUpdateComplete = onUpdateComplete
		self.binFileURL = binFileURL
		self._host = State(initialValue: host)
	}
	
	var body: some View {
		FirmwareOTAUpdateSheet(
			title: "ESP32 WiFi Updater",
			progress: ota.progress,
			statusState: ota.otaState,
			statusMessage: ota.statusMessage,
			inRetryWorkflow: inRetryWorkflow,
			isStartDisabled: accessoryManager.activeDeviceNum == nil,
			onStart: { startWifiProcess() },
			onRetry: {
				inRetryWorkflow = true
				var transaction = Transaction(animation: .none)
				transaction.disablesAnimations = true
				withTransaction(transaction) {
					ota.retry()
				}
			},
			onDismiss: {
				if let onUpdateComplete = self.onUpdateComplete, ota.otaState == .completed {
					onUpdateComplete()
				} else {
					dismiss()
				}
			},
			gameTitle: "ESP32 Wi-Fi OTA"
		)
		.task {
			// Attempt to grab host from current TCP connection if available
			if let connection = accessoryManager.activeConnection?.connection as? TCPConnection {
				self.host = await connection.host.stringValue
			}
		}
		.onDisappear {
			otaTask?.cancel()
			otaTask = nil
			if accessoryManager.otaInProgress {
				releaseRadio()
			}
		}
	}

	/// Hand the radio back to the app: let discovery and auto-connect pick the device up once it
	/// reboots into the new firmware.
	private func releaseRadio() {
		accessoryManager.otaInProgress = false
		accessoryManager.userRequestedConnectionCancellation = false
		accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = true
		accessoryManager.startDiscovery()
	}
	
	// MARK: - Logic
	
	private func startWifiProcess() {
		guard let deviceNum = accessoryManager.activeDeviceNum,
			  let connectedNode = getNodeInfo(id: deviceNum, context: context),
			  let user = connectedNode.user else {
			return
		}
		
		otaTask = Task {
			do {
				if let host {
					let device = accessoryManager.activeConnection?.device
					
					if !alreadyRebooted {
						// Claim the radio before the reboot command goes out. The device reboots
						// into OTA mode as soon as it lands and the connection drops with it; the
						// Firmware screen keys its content off otaInProgress, so without this it
						// swaps to the "please reconnect" placeholder and takes this sheet — and
						// the update — down with it, leaving the device waiting in OTA mode.
						accessoryManager.otaInProgress = true
						accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = false

						// Move heavy file reading/hashing off the Main Actor
						let sha256Digest = try await Task.detached(priority: .userInitiated) {
							let data = try Data(contentsOf: binFileURL)
							return Data(SHA256.hash(data: data))
						}.value
						
						Logger.services.debug("Requesting reboot for OTA with hash: \(sha256Digest as NSData)")
						
						try await accessoryManager.sendRebootOta(fromUser: user, toUser: user, mode: .otaWifi, otaHash: sha256Digest)
						
						// Give the packet a moment to send before disconnecting
						try await Task.sleep(for: .seconds(0.5))
						try await accessoryManager.disconnect()
						alreadyRebooted = true
					}
					
					// The sheet can be dismissed while the reboot settles, which cancels this task
					// and hands the radio back. Do not start a transfer after that.
					guard !Task.isCancelled else { return }

					// Begin the HTTP update
					await ota.startUpdate(host: host, firmwareUrl: self.binFileURL)
					
					// Attempt to reconnect after update. The reconnect needs the gate open, but
					// the sheet stays up: releaseRadio only restores discovery and auto-connect,
					// and the Firmware screen behind it rebuilds once the node is back.
					if let device {
						accessoryManager.otaInProgress = false
						accessoryManager.userRequestedConnectionCancellation = false
						accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = true
						try await Task.sleep(for: .seconds(3))
						try await accessoryManager.connect(to: device, retries: 5)
					}
				}
			} catch {
				Logger.mesh.error("ESP32 OTA Failed: \(error.localizedDescription)")
				releaseRadio()
			}
		}
	}
}

#Preview {
	ESP32WifiOTASheet(
		binFileURL: URL(fileURLWithPath: "/tmp/firmware-esp32-heltec-2.5.18.bin"),
		host: "192.168.1.100"
	)
	.environmentObject(AccessoryManager.shared)
}
