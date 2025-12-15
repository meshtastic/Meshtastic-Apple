//
//  ESP32DFUSheet.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/12/25.
//

import SwiftUI
import OSLog

struct ESP32DFUSheet: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.managedObjectContext) var context
	
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 24) {
					
					// MARK: - Info Card
					VStack(alignment: .leading, spacing: 12) {
						Label("Desktop Required", systemImage: "desktopcomputer")
							.font(.headline)
						
						Text("The recommended way to update ESP32 devices is using the **Web Flasher** on a desktop computer (Chrome-based browser).")
							.fixedSize(horizontal: false, vertical: true)
						
						Text("The **Web Flasher** does not support updating on this device or over USB or BLE.")
							.font(.caption)
							.foregroundStyle(.secondary)
						
						Link(destination: URL(string: "https://flash.meshtastic.org")!) {
							HStack {
								Text("Open Web Flasher")
								Image(systemName: "arrow.up.right")
							}
							.frame(maxWidth: .infinity)
						}
						.buttonStyle(.bordered)
						.controlSize(.regular)
					}
					.padding()
					.background(Color(UIColor.secondarySystemBackground))
					.cornerRadius(12)
					
					Divider()
					
					// MARK: - OTA Section
					VStack(alignment: .leading, spacing: 16) {
						Label("Utilities", systemImage: "exclamationmark.triangle")
							.font(.headline)
							.foregroundStyle(.orange)
						
						Text("For advanced use cases, you can send a reboot command to the node using the following commands:")
							.fixedSize(horizontal: false, vertical: true)
					
						resetIntoOTAButton()
						normalRebootButton()
					}
					.padding(.horizontal)
				}
				.padding(.top)
			}.padding()
			// Standard Navigation Bar Setup
			.navigationTitle("ESP32 Update")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { // Standard placement for "Done" or "Close"
					Button("Done") {
						dismiss()
					}
				}
			}
		}
	}
	

	@ViewBuilder
	func normalRebootButton() -> some View {
		Button {
			let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? 0, context: context)
			if let connectedNode, let user = connectedNode.user {
				Task {
					do {
						try await accessoryManager.sendRebootOta(fromUser: user, toUser: user)
					} catch {
						Logger.mesh.error("Reboot Failed")
					}
				}
			}
		} label: {
			Label("Send Normal Reboot", systemImage: "square.and.arrow.down")
		}.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.frame(maxWidth: .infinity)
			.cornerRadius(10).disabled(accessoryManager.activeDeviceNum == nil)
	}
	
	@ViewBuilder
	func resetIntoOTAButton() -> some View {
		Button {
			let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? 0, context: context)
			if let connectedNode, let user = connectedNode.user {
				Task {
					do {
						try await accessoryManager.sendEnterDfuMode(fromUser: user, toUser: user)
					} catch {
						Logger.mesh.error("Reboot Failed")
					}
				}
			}
		} label: {
			Label(" Send Reboot into DFU", systemImage: "square.and.arrow.down")
		}.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.frame(maxWidth: .infinity)
			.cornerRadius(10).disabled(accessoryManager.activeDeviceNum == nil)
	}
}

#Preview {
	ESP32DFUSheet()
		// Mock environment object for preview to work
		.environmentObject(AccessoryManager())
}
