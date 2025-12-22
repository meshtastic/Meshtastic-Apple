//
//  ESP32WifiOTASheet.swift
//  Meshtastic
//
//  Created by jake on 12/20/25.
//

import Foundation
import SwiftUI
import OSLog

struct ESP32WifiOTASheet: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.managedObjectContext) var context
	@StateObject var ota = ESP32WifiOTAViewModel()

	// The stuff were updating, and the place we're updating it to
	let binFileURL: URL
	@State var host: String?
	
	var body: some View {
		NavigationStack {
			List {
				Section {
					VStack {
						Text("Please do not leave this screen until this process is complete.")
							.multilineTextAlignment(.center)
					}.listRowBackground(Color.clear)
				}
				
				Section {
					VStack(alignment: .leading) {
						Text("Firmware File").font(.caption).foregroundColor(.secondary)
						Text("\(self.binFileURL.lastPathComponent)").font(.caption)
					}
					VStack(alignment: .leading) {
						Text("Network Location").font(.caption).foregroundColor(.secondary)
						Text("\(host ?? "Unknown")").font(.caption)
					}
				} footer: {
					Text("Please be sure this is correct before proceeding.")
				}
				
				Section {
					HStack(alignment: .center) {
						Spacer()
						CircularProgressView(progress: ota.progress, isIndeterminate: (ota.otaState == .preparing), size: 225.0, subtitleText: ota.otaState.rawValue)
							.frame(minHeight: 250.0)
						Spacer()
					}.listRowBackground(Color.clear)
					VStack {
						switch ota.otaState {
						case .idle:
							beginWifiProcessButton()
							
						case .error:
							Text("Error: \(ota.errorMessage, default: "Unknown")")
							
						default:
							Text("\(ota.statusMessage, default: "")")
						}
					}.listRowBackground(Color.clear)
				}.listRowSeparator(.hidden)
			}.navigationTitle("ESP32 WiFi Updater")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { // Standard placement for "Done" or "Close"
					Button("Done") {
						dismiss()
					}.disabled(![.idle, .completed, .error].contains(ota.otaState))
				}
			}
		}.task {
			if let connection = accessoryManager.activeConnection?.connection as? TCPConnection {
				self.host = await connection.host.stringValue
			}
		}.interactiveDismissDisabled(true)

	}
	
	@ViewBuilder
	func beginWifiProcessButton() -> some View {
		Button {
			let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? 0, context: context)
			if let connectedNode, let user = connectedNode.user {
				Task {
					do {
						if let host {
							let device = accessoryManager.activeConnection?.device
							try await accessoryManager.sendRebootOta(fromUser: user, toUser: user, rebootOtaSeconds: 1)
							try await accessoryManager.disconnect()
							await ota.startUpdate(host: host, firmwareUrl: self.binFileURL)
							if let device {
								try await Task.sleep(for: .seconds(3))
								try await accessoryManager.connect(to: device, retries: 5)
							}
						}
					} catch {
						Logger.mesh.error("Reboot Failed")
					}
				}
			}
		} label: {
			Label("Reboot into Wifi OTA Update Mode", systemImage: "square.and.arrow.down")
				.frame(maxWidth: .infinity)
			
		}.buttonStyle(.bordered)
			.controlSize(.large)
			.disabled(accessoryManager.activeDeviceNum == nil)
	}
}
