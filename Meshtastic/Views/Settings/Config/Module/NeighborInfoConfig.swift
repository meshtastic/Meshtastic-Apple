//
//  NeighborInfoConfig.swift
//  Meshtastic
//

import MeshtasticProtobufs
import OSLog
import SwiftUI

struct NeighborInfoConfig: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack

	let node: NodeInfoEntity?

	@State private var enabled = false
	@State private var transmitOverLora = false
	@State private var updateInterval = 0
	@State private var hasChanges: Bool = false

	var body: some View {
		Form {
			ConfigHeader(title: "Neighbor Info", config: \.neighborInfoConfig, node: node, onAppear: setNeighborInfoValues)

			Section(header: Text("Options")) {
				Toggle(isOn: $enabled) {
					Label("Enabled", systemImage: "network")
					Text("Enable neighbor info broadcasting. Periodically sends information about directly-heard neighbors to help visualize mesh topology.")
				}
				.tint(.accentColor)
			}

			if enabled {
				Section(header: Text("Settings")) {
					HStack {
						Label("Update Interval (seconds)", systemImage: "clock")
						Spacer()
						TextField("Update Interval", value: $updateInterval, format: .number)
							.keyboardType(.numberPad)
							.multilineTextAlignment(.trailing)
							.frame(width: 100)
					}
					Text("How often to broadcast neighbor info. Minimum is 14400 seconds (4 hours).")
						.foregroundColor(.gray)
						.font(.callout)

					Toggle(isOn: $transmitOverLora) {
						Label("Transmit over LoRa", systemImage: "antenna.radiowaves.left.and.right")
						Text("Whether to transmit neighbor info over LoRa in addition to MQTT and PhoneAPI. Not available on channels with default key and name.")
					}
					.tint(.accentColor)
				}
			}
		}
		.disabled(!accessoryManager.isConnected || node?.neighborInfoConfig == nil)
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
					var config = ModuleConfig.NeighborInfoConfig()
					config.enabled = enabled
					// A value of 0 means use the firmware default; otherwise enforce the minimum of 14400 seconds
					config.updateInterval = updateInterval == 0 ? 0 : UInt32(max(updateInterval, 14400))
					config.transmitOverLora = transmitOverLora
					_ = try await accessoryManager.saveNeighborInfoModuleConfig(
						config: config,
						fromUser: fromUser,
						toUser: toUser
					)
				}
			}
			}
		}
		.navigationTitle("Neighbor Info Config")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onFirstAppear {
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				let connectedNode = getNodeInfo(id: deviceNum, context: context)
				if let connectedNode {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.neighborInfoConfig == nil {
								Task {
									do {
										Logger.mesh.info("⚙️ Empty or expired neighbor info module config requesting via PKI admin")
										try await accessoryManager.requestNeighborInfoModuleConfig(fromUser: connectedNode.user!, toUser: node.user!)
									} catch {
										Logger.mesh.info("🚨 Request for neighbor info module config failed")
									}
								}
							}
						} else {
							Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
						}
					}
				}
			}
		}
		.onChange(of: enabled) { oldEnabled, newEnabled in
			if oldEnabled != newEnabled && newEnabled != node?.neighborInfoConfig?.enabled { hasChanges = true }
		}
		.onChange(of: updateInterval) { oldInterval, newInterval in
			if oldInterval != newInterval && newInterval != Int(node?.neighborInfoConfig?.updateInterval ?? -1) { hasChanges = true }
		}
		.onChange(of: transmitOverLora) { oldTransmit, newTransmit in
			if oldTransmit != newTransmit && newTransmit != node?.neighborInfoConfig?.transmitOverLora { hasChanges = true }
		}
	}

	private func setNeighborInfoValues() {
		enabled = node?.neighborInfoConfig?.enabled ?? enabled
		updateInterval = Int(node?.neighborInfoConfig?.updateInterval ?? 0)
		transmitOverLora = node?.neighborInfoConfig?.transmitOverLora ?? transmitOverLora
	}
}

#Preview {
	NeighborInfoConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
