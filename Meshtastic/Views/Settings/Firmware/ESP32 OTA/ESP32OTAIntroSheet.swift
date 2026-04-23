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

	/// ESP32 OTA (BLE/WiFi) requires AdminMessage.OTAEvent with otaHash for authentication,
	/// added to Meshtastic firmware in 2.7.18.
	private let minimumOTAVersion = "2.7.18"

	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss
	@Environment(\.managedObjectContext) var context

	let binFileURL: URL

	@State var showWifiUpdater = false
	@State var debugHost: String = ""
	@State var showBLEUpdater = false

	/// True when the connected device's firmware supports the OTAEvent protocol.
	private var firmwareSupportsOTA: Bool {
		accessoryManager.checkIsVersionSupported(forVersion: minimumOTAVersion)
	}

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

				if !firmwareSupportsOTA {
					Section {
						HStack(spacing: 12) {
							Image(systemName: "exclamationmark.triangle.fill")
								.foregroundStyle(.orange)
							VStack(alignment: .leading, spacing: 4) {
								Text("Firmware Update Required")
									.font(.subheadline.bold())
								Text("ESP32 OTA updating requires firmware \(minimumOTAVersion) or later. Update your device firmware using the Web Flasher first.")
									.font(.caption)
									.foregroundStyle(.secondary)
									.fixedSize(horizontal: false, vertical: true)
							}
						}
						.padding(.vertical, 4)
					}
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
							.cornerRadius(10)
							.disabled(accessoryManager.activeDeviceNum == nil || !firmwareSupportsOTA)
						}
						.padding()
						.listRowBackground(Color(UIColor.tertiarySystemBackground))
					}
				case .ble:
					VStack(alignment: .leading, spacing: 12) {
						Label {
							Text("BLE OTA Updating")
						} icon: {
							Image("custom.bluetooth")
						}
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
						.cornerRadius(10)
						.disabled(accessoryManager.activeDeviceNum == nil || !firmwareSupportsOTA)
					}
					.padding()
					.listRowBackground(Color(UIColor.tertiarySystemBackground))
					
				default:
					EmptyView()
				}
				#if DEBUG
				Section("Debug BLE") {
					Button("Manually Start BLE OTA") {
						self.showBLEUpdater = true
					}
				}
				Section("Debug Wifi") {
					TextField("Device IP", text: $debugHost)
					Button("Manually Start WIFI OTA") {
						self.showWifiUpdater = true
					}
				}
				#endif
				
			}.sheet(isPresented: $showWifiUpdater) {
				let theHost: String? = {
					#if DEBUG
					if !debugHost.isEmpty {
						return debugHost
					}
					#endif
					return nil
				}()
				ESP32WifiOTASheet(binFileURL: binFileURL, host: theHost, onUpdateComplete: { dismiss() })
					.environmentObject(accessoryManager)
			}.sheet(isPresented: $showBLEUpdater) {
				ESP32BLEOTASheet(binFileURL: binFileURL, onUpdateComplete: { dismiss() })
					.environmentObject(accessoryManager)
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
		}.textCase(nil)
	}
	
	private enum SupportedOTAMode {
		case none
		case wifi
		case ble
	}
	
	private var OTAMode: SupportedOTAMode {
		guard let connection = accessoryManager.activeConnection?.connection else {
			return .none
		}

		switch connection {
		case is TCPConnection:
			return .wifi
		case is BLEConnection:
			return .ble
		#if targetEnvironment(macCatalyst)
		case is SerialConnection:
			return .wifi // DEBUG
		#endif
		default:
			return .none
		}
	}
}
