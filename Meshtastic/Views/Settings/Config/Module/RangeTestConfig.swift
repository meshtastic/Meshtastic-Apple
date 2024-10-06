//
//  RangeTestConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct RangeTestConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var enabled = false
	@State var sender = 0
	@State var save = false

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Range", config: \.rangeTestConfig, node: node, onAppear: setRangeTestValues)

				Section(header: Text("options")) {
					Toggle(isOn: $enabled) {
						Label("enabled", systemImage: "figure.walk")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)
					Picker("Sender Interval", selection: $sender ) {
						ForEach(SenderIntervals.allCases) { sci in
							Text(sci.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.hidden)
					Text("This device will send out range test messages on the selected interval.")
						.foregroundColor(.gray)
						.font(.callout)

					Toggle(isOn: $save) {
						Label("save", systemImage: "square.and.arrow.down.fill")
						Text("Saves a CSV with the range test message details, currently only available on ESP32 devices with a web server.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.disabled(!(node != nil && node?.metadata?.hasWifi ?? false))

				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.rangeTestConfig == nil)

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if connectedNode != nil {
					var rtc = ModuleConfig.RangeTestConfig()
					rtc.enabled = enabled
					rtc.save = save
					rtc.sender = UInt32(sender)
					let adminMessageId =  bleManager.saveRangeTestModuleConfig(config: rtc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
			.navigationTitle("range.test.config")
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
				// Need to request a RangeTestModuleConfig from the remote node before allowing changes
				if let connectedPeripheral = bleManager.connectedPeripheral, let node {
					Logger.mesh.info("empty range test module config")
					let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
					if let connectedNode {
						if node.num != connectedNode.num {
							if UserDefaults.enableAdministration && node.num != connectedNode.num {
								/// 2.5 Administration with session passkey
								let expiration = node.sessionExpiration ?? Date()
								if expiration < Date() || node.rangeTestConfig == nil {
									_ = bleManager.requestRangeTestModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
								}
							} else {
								/// Legacy Administration
								_ = bleManager.requestRangeTestModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						}
					}
				}
			}
			.onChange(of: enabled) { _, newEnabled in
				if newEnabled != node?.rangeTestConfig?.enabled { hasChanges = true }
			}
			.onChange(of: save) { _, newSave in
				if newSave != node?.rangeTestConfig?.save { hasChanges = true }
			}
			.onChange(of: sender) { _, newSender in
				if newSender != node?.rangeTestConfig?.sender ?? -1 { hasChanges = true }
			}
		}
	}
	func setRangeTestValues() {
		self.enabled = node?.rangeTestConfig?.enabled ?? false
		self.save = node?.rangeTestConfig?.save ?? false
		self.sender = Int(node?.rangeTestConfig?.sender ?? 0)
		self.hasChanges = false
	}
}
