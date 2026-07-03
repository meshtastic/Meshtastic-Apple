//
//  PaxCounterConfig.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 2/25/24.
//

import MeshtasticProtobufs
import SwiftUI
import OSLog

struct PaxCounterConfig: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	let node: NodeInfoEntity?
	
	@State private var enabled = false
	@State private var paxcounterUpdateInterval: UpdateInterval = UpdateInterval(from: 3600)
	@State private var wifiThreshold: Int32 = -80
	@State private var bleThreshold: Int32 = -80
	@State private var hasChanges: Bool = false
	
	var body: some View {
		Form {
			ConfigHeader(title: "PAX Counter Config", config: \.powerConfig, node: node, onAppear: setPaxValues)
			
			Section {
				Toggle(isOn: $enabled) {
					Label("Enabled", systemImage: "figure.walk.motion")
					Text("When enabled the PAX Counter module counts the number of people passing by using WiFi and Bluetooth. Both WiFI and Bluetooth must be disabled for PAX counter to work.")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				.listRowSeparator(.visible)
				if enabled {
					UpdateIntervalPicker(
						config: .paxCounter,
						pickerLabel: "Update Interval",
						selectedInterval: $paxcounterUpdateInterval
					)
					.listRowSeparator(.hidden)
					Text("How often we can send a message to the mesh when people are detected.")
						.foregroundColor(.gray)
						.font(.callout)
					HStack {
						Label("WiFi Threshold", systemImage: "wifi")
						Spacer()
						TextField("WiFi Threshold", value: $wifiThreshold, format: .number)
							.foregroundColor(.gray)
							.multilineTextAlignment(.trailing)
							.keyboardType(.numbersAndPunctuation)
						Text("dBm")
							.foregroundColor(.gray)
					}
					.listRowSeparator(.hidden)
					Text("RSSI threshold for WiFi device counting. Default is −80 dBm.")
						.foregroundColor(.gray)
						.font(.callout)
					HStack {
						Label("BLE Threshold", systemImage: "antenna.radiowaves.left.and.right")
						Spacer()
						TextField("BLE Threshold", value: $bleThreshold, format: .number)
							.foregroundColor(.gray)
							.multilineTextAlignment(.trailing)
							.keyboardType(.numbersAndPunctuation)
						Text("dBm")
							.foregroundColor(.gray)
					}
					.listRowSeparator(.hidden)
					Text("RSSI threshold for BLE device counting. Default is −80 dBm.")
						.foregroundColor(.gray)
						.font(.callout)
				}
			} header: {
				Text("Options")
			}
		}
		.disabled(!accessoryManager.isConnected || node?.powerConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				performConfigSave(
					node: node,
					context: context,
					accessoryManager: accessoryManager,
					hasChanges: $hasChanges,
					dismiss: goBack
				) { fromUser, toUser in
					var config = ModuleConfig.PaxcounterConfig()
					config.enabled = enabled
					config.paxcounterUpdateInterval = UInt32(paxcounterUpdateInterval.intValue)
					config.wifiThreshold = wifiThreshold
					config.bleThreshold = bleThreshold
					_ = try await accessoryManager.savePaxcounterModuleConfig(
						config: config,
						fromUser: fromUser,
						toUser: toUser
					)
				}
			}
			}
		}
		.navigationTitle("PAX Counter Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onFirstAppear {
			// Need to request a PaxCounterModuleConfig from the remote node before allowing changes
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				let connectedNode = getNodeInfo(id: deviceNum, context: context)
				if let connectedNode {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.paxCounterConfig == nil {
								Task {
									do {
										Logger.mesh.info("⚙️ Empty or expired pax counter module config requesting via PKI admin")
										try await accessoryManager.requestPaxCounterModuleConfig(fromUser: connectedNode.user!, toUser: node.user!)
									} catch {
										Logger.mesh.info("🚨 Request for pax counter module config failed")
									}
								}
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
						}
					}
				}
			}
		}
		.onChange(of: enabled) { oldEnabled, newEnabled in
			if oldEnabled != newEnabled && newEnabled != (node?.paxCounterConfig?.enabled ?? false) { hasChanges = true }
		}
		.onChange(of: paxcounterUpdateInterval.intValue) { oldPaxcounterUpdateInterval, newPaxcounterUpdateInterval in
			if oldPaxcounterUpdateInterval != newPaxcounterUpdateInterval {
				let stored = Int(node?.paxCounterConfig?.updateInterval ?? 0)
				let effective = stored == 0 ? 3600 : stored
				if newPaxcounterUpdateInterval != effective { hasChanges = true }
			}
		}
		.onChange(of: wifiThreshold) { oldWifiThreshold, newWifiThreshold in
			if oldWifiThreshold != newWifiThreshold {
				let stored = node?.paxCounterConfig?.wifiThreshold ?? 0
				let effective = stored == 0 ? Int32(-80) : stored
				if newWifiThreshold != effective { hasChanges = true }
			}
		}
		.onChange(of: bleThreshold) { oldBleThreshold, newBleThreshold in
			if oldBleThreshold != newBleThreshold {
				let stored = node?.paxCounterConfig?.bleThreshold ?? 0
				let effective = stored == 0 ? Int32(-80) : stored
				if newBleThreshold != effective { hasChanges = true }
			}
		}
	}
	
	private func setPaxValues() {
		enabled = node?.paxCounterConfig?.enabled ?? enabled
		let storedInterval = Int(node?.paxCounterConfig?.updateInterval ?? 0)
		paxcounterUpdateInterval = UpdateInterval(from: storedInterval == 0 ? 3600 : storedInterval)
		let storedWifi = node?.paxCounterConfig?.wifiThreshold ?? 0
		wifiThreshold = storedWifi == 0 ? -80 : storedWifi
		let storedBle = node?.paxCounterConfig?.bleThreshold ?? 0
		bleThreshold = storedBle == 0 ? -80 : storedBle
		hasChanges = false
	}
}

#Preview {
	PaxCounterConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
