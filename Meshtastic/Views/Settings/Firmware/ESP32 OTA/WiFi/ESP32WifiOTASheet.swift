//
//  ESP32WifiOTASheet.swift
//  Meshtastic
//
//  Created by jake on 12/20/25.
//

import Foundation
import SwiftUI
import OSLog
import CryptoKit

struct ESP32WifiOTASheet: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.managedObjectContext) var context
	@StateObject var ota = ESP32WifiOTAViewModel()
	
	// The stuff were updating, and the place we're updating it to
	let binFileURL: URL
	@State var host: String?
	@State var alreadyRebooted: Bool = false
	
	init(binFileURL: URL, host: String? = nil) {
		self.binFileURL = binFileURL
		self._host = State(initialValue: host)
	}
	
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
							retryButton()
							
						default:
							Text("\(ota.statusMessage, default: "")")
								.frame(maxWidth: .infinity)
								.multilineTextAlignment(.center)
								.font(.headline)
						}
					}.listRowBackground(Color.clear)
				}.listRowSeparator(.hidden)
			}.listSectionSpacing(.compact)
			.navigationTitle("ESP32 WiFi Updater")
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
	func retryButton() -> some View {
		VStack(spacing: 12) {
			Text("Error: \(ota.statusMessage)")
				.multilineTextAlignment(.center)
				.foregroundStyle(.red)
				.font(.headline)
			
			Button {
				var transaction = Transaction(animation: .none)
				transaction.disablesAnimations = true
				
				withTransaction(transaction) {
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
							if !alreadyRebooted {
								let data = try Data(contentsOf: binFileURL)
								let digest = SHA256.hash(data: data)
								let sha256Digest = Data(digest)
								Logger.services.debug("Requesting reboot for OTA with hash: \(digest)")

								try await accessoryManager.sendRebootOta(fromUser: user, toUser: user, mode: .otaWifi, otaHash: sha256Digest)
								try await Task.sleep(for: .seconds(0.5))
								try await accessoryManager.disconnect()
								alreadyRebooted = true
							}
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
