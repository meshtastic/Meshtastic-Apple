//
//  ESP32DFUSheet.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/12/25.
//

import SwiftUI
import OSLog
import Network

struct ESP32DFUSheet: View {
	private enum Step {
		case intro
		case updater
	}
	
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.managedObjectContext) var context
	
	@StateObject var ota = Esp32WifiOTAViewModel()
	let binFileURL: URL
	@State var host: NWEndpoint.Host?
	@State private var step: Step = .intro
	
	init(binFileURL: URL) {
		self.binFileURL = binFileURL
	}
	
	var body: some View {
		NavigationStack {
			ScrollView {
				switch step {
				case .intro:
					VStack(spacing: 24) {
						
						// MARK: - Info Card
						VStack(alignment: .leading, spacing: 12) {
							Label("Desktop Recommended", systemImage: "desktopcomputer")
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
						
						VStack(alignment: .leading, spacing: 12) {
							Label("WiFi OTA Updating", systemImage: "wifi")
								.font(.headline)
							
							HStack(alignment: .top, spacing: 12) {
								Image(systemName: "lock.shield")
									.font(.title2)
									.foregroundStyle(.blue)
								
								Text("Advanced Users Only.")
									.font(.callout)
							}
							
							Text("If you device has the WiFi updater loaded into the OTA_1 partition, you can attempt to use the WiFi update process.")
								.font(.caption)
								.foregroundStyle(.secondary)
							
							Button(role: .destructive) {
								self.step = .updater
							} label: {
								Text("I Know What I'm Doing")
							}
							.buttonStyle(.borderedProminent)
							.controlSize(.large)
							.frame(maxWidth: .infinity)
							.cornerRadius(10).disabled(accessoryManager.activeDeviceNum == nil)
						}
						.padding()
						.background(Color(UIColor.secondarySystemBackground))
						.cornerRadius(12)
					}.padding(.top)
						.padding()
					
				case .updater:
					Text("WiFi Firmware Update")
						.font(.headline)
					
					Text("Please do not leave this screen until this process is complete.")
						.multilineTextAlignment(.center)
						.padding()
					
					CircularProgressView(progress: ota.progress, isIndeterminate: (ota.otaState == .handshaking), size: 255.0, subtitleText: ota.otaState.rawValue)
					
					VStack {
						switch ota.otaState {
						case .idle:
							beginUpdateProcessButton()
							
						case .error:
							Text("Error: \(ota.errorMessage, default: "Unknown")")
							
						default:
							Text("\(ota.statusMessage, default: "")")
						}
					}.frame(minHeight: 250.0)
						.padding()
				}
			}.navigationTitle("ESP32 Update")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) { // Standard placement for "Done" or "Close"
						Button("Done") {
							dismiss()
						}.disabled(![.idle, .success, .error].contains(ota.otaState))
					}
				}
			
		}// Standard Navigation Bar Setup
		
		.onFirstAppear {
			if let connection = accessoryManager.activeConnection?.connection as? TCPConnection {
				self.host = connection.host
			}
		}
	}
	
	@ViewBuilder
	func beginUpdateProcessButton() -> some View {
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
			Label("Reboot into OTA Update Mode", systemImage: "square.and.arrow.down")
		}.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.frame(maxWidth: .infinity)
			.cornerRadius(10).disabled(accessoryManager.activeDeviceNum == nil)
	}
}
