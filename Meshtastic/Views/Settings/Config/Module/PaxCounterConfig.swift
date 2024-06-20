//
//  PaxCounterConfig.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 2/25/24.
//

import MeshtasticProtobufs
import SwiftUI

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
			ConfigHeader(title: "config.module.paxcounter.title", config: \.powerConfig, node: node, onAppear: setPaxValues)

			Section {
				Toggle(isOn: $enabled) {
					Label("enabled", systemImage: "figure.walk.motion")
					Text("config.module.paxcounter.enabled.description")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				.listRowSeparator(.visible)
				if enabled {
					Picker("config.module.paxcounter.updateinterval", selection: $paxcounterUpdateInterval) {
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
				Text("options")
			}
		}
		.disabled(self.bleManager.connectedPeripheral == nil || node?.powerConfig == nil)
		.navigationTitle("config.module.paxcounter.title")
		.navigationBarItems(trailing: ZStack {
			ConnectedDevice(
				bluetoothOn: bleManager.isSwitchedOn,
				deviceConnected: bleManager.connectedPeripheral != nil,
				name: bleManager.connectedPeripheral?.shortName ?? "?"
			)
		})
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}

			setPaxValues()
			// Need to request a PAX Counter module config from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node, node.paxCounterConfig == nil {
				if let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context) {
					_ = bleManager.requestPaxCounterModuleConfig(
						fromUser: connectedNode.user!,
						toUser: node.user!,
						adminIndex: connectedNode.myInfo?.adminIndex ?? 0
					)
				}
			}
		}
		.onChange(of: enabled) {
			if let val = node?.paxCounterConfig?.enabled {
				hasChanges = $0 != val
			}
		}
		.onChange(of: paxcounterUpdateInterval) {
			if let val = node?.paxCounterConfig?.updateInterval {
				hasChanges = $0 != val
			}
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			guard let connectedPeripheral = bleManager.connectedPeripheral,
			      let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context),
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
		paxcounterUpdateInterval = Int(node?.paxCounterConfig?.updateInterval ?? 900)
	}
}
