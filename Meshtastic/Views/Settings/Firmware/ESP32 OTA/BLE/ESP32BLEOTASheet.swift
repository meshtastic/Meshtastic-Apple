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
					
					// Give some time for any final incoming notifications
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
			}
		}
	}
}

#Preview {
	ESP32BLEOTASheet(binFileURL: URL(fileURLWithPath: "/tmp/firmware-esp32-s3-2.5.18.bin"))
		.environmentObject(AccessoryManager.shared)
}
