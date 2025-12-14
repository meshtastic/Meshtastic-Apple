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
		NavigationView { // Use a NavigationView for a title bar
			VStack(alignment: .leading, spacing: 20.0) {
				Text("ESP32 Device Firmware Update")
					.font(.title)
				Text("Currently the recommended way to update ESP32 devices is using the web flasher on a desktop computer from a chrome based browser. It does not work on mobile devices or over BLE.")
					.font(.body)
				Link("Web Flasher", destination: URL(string: "https://flash.meshtastic.org")!)
					.font(.body)
					.padding()
				Text("ESP 32 OTA update is a work in progress, click the button below to send your device a reboot into ota admin message.")
					.font(.body)
				HStack(alignment: .center) {
					Spacer()
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
						Label("Send Reboot OTA", systemImage: "square.and.arrow.down")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.regular)
					.padding(5)
					Spacer()
				}
			}.padding(20.0)
				.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					// 2. Create a button that calls dismiss()
					Button("Done") {
						dismiss()
					}
				}
			}
		}
	}
}

#Preview {
	ESP32DFUSheet()
}
