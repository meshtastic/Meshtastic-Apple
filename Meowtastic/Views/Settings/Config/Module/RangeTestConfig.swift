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
				ConfigHeader(title: "Range", config: \.rangeTestConfig, node: node)

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
				trailing: ConnectedDevice(ble: bleManager)
			)
			.onAppear {
				if self.bleManager.context == nil {
					self.bleManager.context = context
				}
				setRangeTestValues()
				// Need to request a RangeTestModule Config from the remote node before allowing changes
				if bleManager.connectedPeripheral != nil && node?.rangeTestConfig == nil {
					Logger.mesh.debug("empty range test module config")
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if node != nil && connectedNode != nil {
						_ = bleManager.requestRangeTestModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					}
				}
			}
			.onChange(of: enabled) { newEnabled in
				if node != nil && node!.rangeTestConfig != nil {
					if newEnabled != node!.rangeTestConfig!.enabled { hasChanges = true }
				}
			}
			.onChange(of: save) { newSave in
				if node != nil && node!.rangeTestConfig != nil {
					if newSave != node!.rangeTestConfig!.save { hasChanges = true }
				}
			}
			.onChange(of: sender) { newSender in
				if node != nil && node!.rangeTestConfig != nil {
					if newSender != node!.rangeTestConfig!.sender { hasChanges = true }
				}
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
