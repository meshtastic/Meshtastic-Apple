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
	@Environment(\.managedObjectContext) private var context
	@EnvironmentObject private var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	let node: NodeInfoEntity?

	@State private var enabled = false
	@State private var paxcounterUpdateInterval = 0
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
					Picker("Update Interval", selection: $paxcounterUpdateInterval) {
						ForEach(UpdateIntervals.allCases) { at in
							if at.rawValue >= 300 {
								Text(at.description)
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.hidden)
					Text("config.module.paxcounter.updateinterval.description")
						.foregroundColor(.gray)
						.font(.callout)
				}
			} header: {
				Text("Options")
			}
		}
		.disabled(self.bleManager.connectedPeripheral == nil || node?.powerConfig == nil)
		.navigationTitle("config.module.paxcounter.title")
		.navigationBarItems(trailing: ZStack {
			ConnectedDevice(
				bluetoothOn: bleManager.isSwitchedOn,
				deviceConnected: bleManager.connectedPeripheral != nil,
				name: "\(bleManager.connectedPeripheral?.shortName ?? "?")"
			)
		})
		.onFirstAppear {
			// Need to request a PaxCounterModuleConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.paxCounterConfig == nil {
								Logger.mesh.info("⚙️ Empty or expired pax counter module config requesting via PKI admin")
								_ = bleManager.requestPaxCounterModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin, empty pax counter module config")
							_ = bleManager.requestPaxCounterModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
						}
					}
				}
			}
		}
		.onChange(of: enabled) { oldEnabled, newEnabled in
			if oldEnabled != newEnabled && newEnabled != node?.paxCounterConfig?.enabled { hasChanges = true }
		}
		.onChange(of: paxcounterUpdateInterval) { oldPaxcounterUpdateInterval, newPaxcounterUpdateInterval in
			if oldPaxcounterUpdateInterval != newPaxcounterUpdateInterval && newPaxcounterUpdateInterval != node?.paxCounterConfig?.updateInterval ?? -1 { hasChanges = true }
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			guard let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context),
				  let fromUser = connectedNode.user,
				  let toUser = node?.user else {
				return
			}

			var config = ModuleConfig.PaxcounterConfig()
			config.enabled = enabled
			config.paxcounterUpdateInterval = UInt32(paxcounterUpdateInterval)

			let adminMessageId = bleManager.savePaxcounterModuleConfig(
				config: config,
				fromUser: fromUser,
				toUser: toUser,
				adminIndex: connectedNode.myInfo?.adminIndex ?? 0
			)
			if adminMessageId > 0 {
				// Should show a saved successfully alert once I know that to be true
				// for now just disable the button after a successful save
				hasChanges = false
				goBack()
			}
		}
	}

	private func setPaxValues() {
		enabled = node?.paxCounterConfig?.enabled ?? enabled
		paxcounterUpdateInterval = Int(node?.paxCounterConfig?.updateInterval ?? 1800)
	}
}
