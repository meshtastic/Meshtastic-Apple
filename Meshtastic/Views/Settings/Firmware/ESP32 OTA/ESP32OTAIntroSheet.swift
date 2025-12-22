//
//  ESP32DFUSheet.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/12/25.
//

import SwiftUI
import OSLog
import Network

struct ESP32OTAIntroSheet: View {
	private enum Step {
		case intro
		case updater
	}
	
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.managedObjectContext) var context
	
	let binFileURL: URL
	
	
	@State var showWifiUpdater = false
	@State var showBLEUpdater = false
	
	var body: some View {
		NavigationStack {
			List {
				Section {
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
					}.listRowBackground(Color(UIColor.tertiarySystemBackground))
					
				} footer: {
					Color.clear.frame(height: 5)
				}
				
				switch OTAMode {
				case .wifi:
					Section {
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
							
							Text("If you device has the proper updater loaded into the OTA_1 partition, you can attempt to use the WiFi update process.")
								.font(.caption)
								.foregroundStyle(.secondary)
							
							Button(role: .destructive) {
								self.showWifiUpdater = true
							} label: {
								Text("I Know What I'm Doing")
							}
							.buttonStyle(.borderedProminent)
							.controlSize(.large)
							.frame(maxWidth: .infinity)
							.cornerRadius(10).disabled(accessoryManager.activeDeviceNum == nil)
						}
						.padding()
						.listRowBackground(Color(UIColor.tertiarySystemBackground))
					}
				case .ble:
					VStack(alignment: .leading, spacing: 12) {
						Label("BLE OTA Updating", systemImage: "wifi")
							.font(.headline)
						
						HStack(alignment: .top, spacing: 12) {
							Image(systemName: "lock.shield")
								.font(.title2)
								.foregroundStyle(.blue)
							
							Text("Advanced Users Only.")
								.font(.callout)
						}
						
						Text("If you device has the proper updater loaded into the OTA_1 partition, you can attempt to use the BLE update process.")
							.font(.caption)
							.foregroundStyle(.secondary)
						
						Button(role: .destructive) {
							self.showBLEUpdater = true
						} label: {
							Text("I Know What I'm Doing")
						}
						.buttonStyle(.borderedProminent)
						.controlSize(.large)
						.frame(maxWidth: .infinity)
						.cornerRadius(10).disabled(accessoryManager.activeDeviceNum == nil)
					}
					.padding()
					.listRowBackground(Color(UIColor.tertiarySystemBackground))
					
				default:
					EmptyView()
				}
				
			}.sheet(isPresented: $showWifiUpdater) {
				ESP32WifiOTASheet(binFileURL: binFileURL)
			}.sheet(isPresented: $showBLEUpdater) {
				ESP32BLEOTASheet(binFileURL: binFileURL)
			}
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
	
	private enum SupportedOTAMode {
		case none
		case wifi
		case ble
	}
	
	private var OTAMode: SupportedOTAMode {
		if let connection = accessoryManager.activeConnection?.connection {
			if connection is TCPConnection {
				return .wifi
			} else if connection is BLEConnection {
				return .ble
			}
			
		}
		return .none
	}
	//	func beginBLEProcessButton() -> some View {
	//		Button {
	//			let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? 0, context: context)
	//			if let connectedNode, let user = connectedNode.user {
	//				Task {
	//					do {
	//						if let host {
	//							let device = accessoryManager.activeConnection?.device
	//							try await accessoryManager.sendRebootOta(fromUser: user, toUser: user, rebootOtaSeconds: 2)
	//							try await accessoryManager.disconnect()
	//							await ota.startUpdate(host: host, firmwareUrl: self.binFileURL)
	//							if let device {
	//								try await Task.sleep(for: .seconds(3))
	//								try await accessoryManager.connect(to: device, retries: 5)
	//							}
	//						}
	//					} catch {
	//						Logger.mesh.error("Reboot Failed")
	//					}
	//				}
	//			}
	//		} label: {
	//			Label("Reboot into BLE OTA Update Mode", systemImage: "square.and.arrow.down")
	//				.frame(maxWidth: .infinity)
	//		}.buttonStyle(.bordered)
	//			.controlSize(.large)
	//			.disabled(accessoryManager.activeDeviceNum == nil)
	//	}
}
