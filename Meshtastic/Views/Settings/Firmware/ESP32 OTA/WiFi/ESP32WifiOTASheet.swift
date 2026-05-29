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

	init(binFileURL: URL, host: String? = nil, onUpdateComplete: (() -> Void)? = nil) {
		self.onUpdateComplete = onUpdateComplete
		self.binFileURL = binFileURL
		self._host = State(initialValue: host)
	}
	
	var body: some View {
		NavigationStack {
			List {
				Section {
					VStack(alignment: .leading) {
						Text("Firmware File").font(.caption).foregroundColor(.secondary)
						Text("\(self.binFileURL.lastPathComponent)").font(.caption)
					}
					VStack(alignment: .leading) {
						Text("Network Location").font(.caption).foregroundColor(.secondary)
						Text("\(host ?? "Unknown")").font(.caption)
					}
				} header: {
					Text("Please do not leave this screen until this process is complete.")
						.multilineTextAlignment(.center)
				} footer: {
					Text("Please be sure this is correct before proceeding.")
				}
				
				Section {
					HStack(alignment: .center) {
						Spacer()
						
						// MARK: - Progress View
						CircularProgressView(
							progress: ota.progress,
							isIndeterminate: (ota.otaState == .preparing),
							isError: (ota.otaState == .error),
							size: 225.0,
							// If error, we show only the triangle (nil).
							// The detailed status message is shown below the ring.
							subtitleText: (ota.otaState == .error) ? nil : ota.otaState.rawValue
						)
						.frame(minHeight: 250.0)
						
						Spacer()
					}
					.listRowBackground(Color.clear)
					
					VStack(spacing: 12) {
						if ota.otaState != .idle {
							Text("\(ota.statusMessage)")
								.frame(maxWidth: .infinity)
								.multilineTextAlignment(.center)
								.font(.headline)
								.foregroundStyle(ota.otaState == .error ? .red : .primary)
						}

						switch ota.otaState {
						case .idle:
							beginWifiProcessButton()
							
						case .error:
							retryButton()
							
						default:
							EmptyView()
						}
					}
					.listRowBackground(Color.clear)
				}
				.listRowSeparator(.hidden)
			}
			.listSectionSpacing(.compact)
			.navigationTitle("ESP32 WiFi Updater")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") {
						if let onUpdateComplete = self.onUpdateComplete, ota.otaState == .completed {
							onUpdateComplete()
						} else {
							dismiss()
						}
					}
					.disabled(![.idle, .completed, .error].contains(ota.otaState))
				}
			}
		}
		.task {
			// Attempt to grab host from current TCP connection if available
			if let connection = accessoryManager.activeConnection?.connection as? TCPConnection {
				self.host = await connection.host.stringValue
			}
		}
		.interactiveDismissDisabled(true)
	}
	
	// MARK: - Component Views
	
	@ViewBuilder
	func retryButton() -> some View {
		Button {
			inRetryWorkflow = true
			
			// Disable animations for the immediate state reset
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
	
	@ViewBuilder
	func beginWifiProcessButton() -> some View {
		Button {
			startWifiProcess()
		} label: {
			if self.inRetryWorkflow {
				Label("Retry Update", systemImage: "arrow.clockwise")
					.frame(maxWidth: .infinity)
			} else {
				Label("Reboot & Start Update", systemImage: "square.and.arrow.down")
					.frame(maxWidth: .infinity)
			}
		}
		.buttonStyle(.bordered)
		.controlSize(.large)
		.disabled(accessoryManager.activeDeviceNum == nil)
	}
	
	// MARK: - Logic
	
	private func startWifiProcess() {
		guard let deviceNum = accessoryManager.activeDeviceNum,
			  let connectedNode = getNodeInfo(id: deviceNum, context: context),
			  let user = connectedNode.user else {
			return
		}
		
		Task {
			do {
				if let host {
					let device = accessoryManager.activeConnection?.device
					
					if !alreadyRebooted {
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
						
						await MainActor.run { alreadyRebooted = true }
					}
					
					// Begin the HTTP update
					await ota.startUpdate(host: host, firmwareUrl: self.binFileURL)
					
					// Attempt to reconnect after update
					if let device {
						try await Task.sleep(for: .seconds(3))
						try await accessoryManager.connect(to: device, retries: 5)
					}
				}
			} catch {
				Logger.mesh.error("ESP32 OTA Failed: \(error.localizedDescription)")
			}
		}
	}
}
