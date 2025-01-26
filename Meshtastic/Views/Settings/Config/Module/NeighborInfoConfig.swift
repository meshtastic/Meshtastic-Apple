//
//  NeighborInfoConfig.swift
//  Meshtastic
//
//  Created by Matthew Davies on 1/25/25.
//

import MeshtasticProtobufs
import Foundation
import SwiftUI
import OSLog

struct NeighborInfoConfig: View {
	
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.managedObjectContext) var context
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var enabled = false
	@State var updateInterval = 21600

	var body: some View {
		let x = print(node?.neighborInfoConfig)
		let y = print("updateInterval: \(updateInterval)")
		VStack {
			Form {
				ConfigHeader(title: "neighbor.info", config: \.neighborInfoConfig, node: node, onAppear: setNeighborInfoValues)
				
				Section(header: Text("options")) {
					Toggle(isOn: $enabled) {
						Label("Enabled", systemImage: enabled ? "checkmark.circle.fill" : "xmark.circle")
						Text("Enable neighbor info")
					}

					Picker("Update Interval", selection: $updateInterval ) {
						ForEach(UpdateIntervals.allCases) { ui in
							if ui.rawValue >= 14400 {
								Text(ui.description)
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.hidden)
					Text("How often neighbor info packets are sent out over the mesh. Default is 6 hours.")
						.foregroundColor(.gray)
						.font(.callout)
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.neighborInfoConfig == nil)
			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if connectedNode != nil {
					var nic = ModuleConfig.NeighborInfoConfig()
					nic.enabled = enabled
					nic.updateInterval = UInt32(updateInterval)
					let adminMessageId = bleManager.saveNeighborInfoConfig(config: nic, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
			.navigationTitle("neighbor.info")
			.navigationBarItems(
				trailing: ZStack {
					ConnectedDevice(
						bluetoothOn: bleManager.isSwitchedOn,
						deviceConnected: bleManager.connectedPeripheral != nil,
						name: bleManager.connectedPeripheral?.shortName ?? "?"
					)
				}
			)
			.onFirstAppear {
				if let connectedPeripheral = bleManager.connectedPeripheral, let node {
					let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
					if let connectedNode {
						if node.num != connectedNode.num {
							if UserDefaults.enableAdministration && node.num != connectedNode.num {
								/// 2.5 Administration with session passkey
								let expiration = node.sessionExpiration ?? Date()
								if expiration < Date() || node.neighborInfoConfig == nil {
									Logger.mesh.info("⚙️ Empty or expired telemetry module config requesting via PKI admin")
									_ = bleManager.requestNeighborInfoModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
								}
							} else {
								/// Legacy Administration
								Logger.mesh.info("☠️ Using insecure legacy admin, empty telemetry module config")
								_ = bleManager.requestNeighborInfoModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						}
					}
				}
			}
			.onChange(of: enabled) { _, newEnabled in
				if newEnabled != node?.neighborInfoConfig?.enabled { hasChanges = true }
			}
			.onChange(of: updateInterval) { _, newUpdateInterval in
				if newUpdateInterval != node?.neighborInfoConfig?.updateInterval ?? -1 { hasChanges = true }
			}
		}
	}
	
	func setNeighborInfoValues() {
		self.enabled = node?.neighborInfoConfig?.enabled ?? false
		let updateInterval = (node?.neighborInfoConfig?.updateInterval ?? 21600) > 0 ? (node?.neighborInfoConfig?.updateInterval ?? 21600) : 21600
		self.updateInterval = Int(updateInterval)
	}
}
