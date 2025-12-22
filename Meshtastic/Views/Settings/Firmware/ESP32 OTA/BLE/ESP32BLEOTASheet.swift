//
//  ESP3BLEOTASheet.swift
//  Meshtastic
//
//  Created by jake on 12/20/25.
//

import Foundation
import SwiftUI
import OSLog
import CoreBluetooth


struct ESP32BLEOTASheet: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.managedObjectContext) var context
	@StateObject var ota = ESP32BLEOTAViewModel2()

	// The stuff were updating, and the place we're updating it to
	let binFileURL: URL
	@State var peripheral: CBPeripheral?
	
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
						Text("BLE Device").font(.caption).foregroundColor(.secondary)
						Text("\(peripheral?.name, default: "Unknown")").font(.caption)
						Text("\(peripheral?.identifier, default: "Unknown")").font(.caption)
					}
				} footer: {
					Text("Please be sure this is correct before proceeding.")
				}
				
				Section {
					HStack(alignment: .center) {
						Spacer()
						CircularProgressView(progress: ota.transferProgress / 100.0, isIndeterminate: (ota.otaStatus == .preparing), size: 225.0, subtitleText: ota.otaStatus.rawValue)
							.frame(minHeight: 250.0)
						Spacer()
					}.listRowBackground(Color.clear)
					VStack {
						if ota.otaStatus == .idle {
							beginBLEProcessButton()
						} else {
							Text("\(ota.statusMessage)")
								.frame(maxWidth: .infinity)
								.multilineTextAlignment(.center)
						}
					}.listRowBackground(Color.clear)
				}.listRowSeparator(.hidden)
			}.navigationTitle("ESP32 BLE Updater")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { // Standard placement for "Done" or "Close"
					Button("Done") {
						dismiss()
					}.disabled(![.idle, .completed, .error].contains(ota.otaStatus))
				}
			}
		}.task {
			if let connection = accessoryManager.activeConnection?.connection as? BLEConnection {
				self.peripheral = await connection.peripheral
			}
		}.interactiveDismissDisabled(true)

	}
	
	@ViewBuilder
	func beginBLEProcessButton() -> some View {
		Button {
			let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? 0, context: context)
			if let connectedNode, let user = connectedNode.user {
				Task {
					do {
						if let peripheral {
							try await accessoryManager.sendRebootOta(fromUser: user, toUser: user, rebootOtaSeconds: 2)
							try await accessoryManager.disconnect()

							ota.startOTA(binURL: binFileURL)
							//ota.startOTA(peripheral: peripheral, binFileURL: binFileURL)
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
