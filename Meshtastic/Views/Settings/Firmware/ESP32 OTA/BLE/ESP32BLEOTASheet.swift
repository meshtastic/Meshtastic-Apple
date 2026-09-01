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
	
	// The stuff we're updating, and the place we're updating it to
	let binFileURL: URL

	// To dismiss the intro sheet when complete.
	var onUpdateComplete: (() -> Void)?

	@State var peripheral: CBPeripheral?
	/// Retained so dismissing the sheet cancels it. Without this the flow could resume after
	/// cleanup had already handed the radio back and start a transfer against a reconnected node.
	@State private var otaTask: Task<Void, Never>?
	
	var body: some View {
		FirmwareOTAUpdateSheet(
			title: "ESP32 BLE Updater",
			progress: ota.transferProgress,
			statusState: ota.otaStatus,
			statusMessage: ota.statusMessage,
			inRetryWorkflow: inRetryWorkflow,
			isStartDisabled: accessoryManager.activeDeviceNum == nil,
			onStart: { startBLEProcess() },
			onRetry: {
				inRetryWorkflow = true
				var transaction = Transaction(animation: .none)
				transaction.disablesAnimations = true
				withTransaction(transaction) {
					ota.retry()
				}
			},
			onDismiss: {
				if let onUpdateComplete, ota.otaStatus == .completed {
					onUpdateComplete()
				} else {
					dismiss()
				}
			},
			gameTitle: "ESP32 BLE OTA"
		)
		.task {
			// Attempt to grab peripheral from current BLE connection
			if let connection = accessoryManager.activeConnection?.connection as? BLEConnection {
				self.peripheral = await connection.peripheral
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

	/// Hand the radio back to the app: restart discovery and let auto-connect pick the device up
	/// once it reboots into the new firmware.
	private func releaseRadio() {
		accessoryManager.otaInProgress = false
		accessoryManager.userRequestedConnectionCancellation = false
		accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = true
		accessoryManager.startDiscovery()
	}
	
	// MARK: - Logic
	
	private func startBLEProcess() {
		// Safe unwrap of required data
		guard let deviceNum = accessoryManager.activeDeviceNum,
			  let connectedNode = getNodeInfo(id: deviceNum, context: context),
			  let user = connectedNode.user else {
			return
		}
		
		otaTask = Task {
			do {
				if !rebootSuccessful {
					// 0. Claim the radio before the reboot command goes out. The device reboots into
					// OTA mode as soon as it lands, and the Firmware screen keys its content off
					// otaInProgress — a disconnect arriving while this is still false tears this
					// sheet down mid-update and leaves the device in OTA mode with nothing driving
					// it. Stopping discovery here also keeps the teardown from re-arming it.
					accessoryManager.otaInProgress = true
					accessoryManager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = false
					accessoryManager.stopDiscovery()

					// 1. Move file reading/hashing to a detached task to avoid blocking Main Thread
					let sha256Digest = try await Task.detached(priority: .userInitiated) {
						let data = try Data(contentsOf: binFileURL)
						let digest = SHA256.hash(data: data)
						return Data(digest)
					}.value
					
					// 2. Send the reboot command via existing connection
					try await accessoryManager.sendRebootOta(fromUser: user, toUser: user, mode: .otaBle, otaHash: sha256Digest)
					rebootSuccessful = true
					
					// Give some time for any final incoming notifications
					try await Task.sleep(for: .seconds(1.0))

					// 3. Disconnect app so the ViewModel can grab the new OTA-Mode advertisement
					try await accessoryManager.disconnect()

					// 4. Wait briefly for device to reboot
					try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
				}
				
				// The sheet can be dismissed during either sleep above, which cancels this task
				// and hands the radio back. Do not start a transfer after that.
				guard !Task.isCancelled else { return }

				// 5. Start the OTA process. Discovery and auto-connect are restored when this
				// sheet closes, not here: clearing the flag on completion lets the Firmware
				// screen rebuild and dismiss the sheet before the result is read.
				await ota.startOTA(binURL: binFileURL, desiredPeripheral: peripheral?.identifier)

			} catch {
				Logger.mesh.error("ESP32 BLE OTA Failed: \(error.localizedDescription)")
				releaseRadio()
			}
		}
	}
}

#Preview {
	ESP32BLEOTASheet(binFileURL: URL(fileURLWithPath: "/tmp/firmware-esp32-s3-2.5.18.bin"))
		.environmentObject(AccessoryManager.shared)
}
