//
//  DetectionSensorModule.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/16/23.
//
import SwiftUI

struct DetectionSensorConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	var node: NodeInfoEntity?
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges: Bool = false
	@State var enabled = false

	var body: some View {

		Form {
			if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
				Text("There has been no response to a request for device metadata over the admin channel for this node.")
					.font(.callout)
					.foregroundColor(.orange)

			} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
				// Let users know what is going on if they are using remote admin and don't have the config yet
				if node?.mqttConfig == nil {
					Text("Detection Sensor config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
						.font(.callout)
						.foregroundColor(.orange)
				} else {
					Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
						.font(.title3)
						.onAppear {
							setDetectionSensorValues()
						}
				}
			} else if node != nil && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? 0 {
				Text("Configuration for: \(node?.user?.longName ?? "Unknown")")
					.font(.title3)
			} else {
				Text("Please connect to a radio to configure settings.")
					.font(.callout)
					.foregroundColor(.orange)
			}
			Section(header: Text("options")) {
				Toggle(isOn: $enabled) {
					Label("enabled", systemImage: "dot.radiowaves.right")
				}
			}
		}
		.scrollDismissesKeyboard(.interactively)
		.disabled(self.bleManager.connectedPeripheral == nil || node?.mqttConfig == nil)

		Button {
			isPresentingSaveConfirm = true
		} label: {
			Label("save", systemImage: "square.and.arrow.down")
		}
		.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.padding()
		.confirmationDialog(
			"are.you.sure",
			isPresented: $isPresentingSaveConfirm,
			titleVisibility: .visible
		) {
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
			if connectedNode != nil {
				let nodeName = node?.user?.longName ?? "unknown".localized
				let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
				Button(buttonText) {
					var dsc = DetectionSensorConfig()
					dsc.enabled = self.enabled
//					let adminMessageId =  bleManager.saveMQTTConfig(config: mqtt, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
//					if adminMessageId > 0 {
//						// Should show a saved successfully alert once I know that to be true
//						// for now just disable the button after a successful save
//						hasChanges = false
//						goBack()
//					}
				}
			}
		}
		message: {
			Text("config.save.confirm")
		}
		.navigationTitle("mqtt.config")
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			self.bleManager.context = context
			setDetectionSensorValues()

			// Need to request a TelemetryModuleConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.mqttConfig == nil {
				print("empty mqtt module config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestMqttModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: enabled) { newEnabled in
			if node != nil && node?.detectionSensorConfig != nil {
				if newEnabled != node!.detectionSensorConfig!.enabled { hasChanges = true }
			}
		}
	}
	
	func setDetectionSensorValues() {
		self.enabled = (node?.detectionSensorConfig?.enabled ?? false)
		self.hasChanges = false
	}
}
