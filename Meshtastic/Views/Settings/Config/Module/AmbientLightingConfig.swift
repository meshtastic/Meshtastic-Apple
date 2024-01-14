//
//  AmbientLightingConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/26/23
//

import SwiftUI
@available(iOS 17.0, macOS 14.0, *)
struct AmbientLightingConfig: View {
	@Environment(\.self) var environment
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var ledState: Bool = false
	@State var current = 10
	@State var red = 0
	@State var green = 0
	@State var blue = 0
	@State private var color = Color(red: 51, green: 199, blue: 88) // Color(.sRGB, red: 0.98, green: 0.9, blue: 0.2)
	@State private var components: Color.Resolved?
	var body: some View {
		VStack {
			Form {
				if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					Text("There has been no response to a request for device metadata over the admin channel for this node.")
						.font(.callout)
						.foregroundColor(.orange)

				} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					// Let users know what is going on if they are using remote admin and don't have the config yet
					if node?.rtttlConfig == nil {
						Text("Ambient Lighting config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
							.font(.callout)
							.foregroundColor(.orange)
					} else {
						Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
							.font(.title3)
							.onAppear {
								setAmbientLightingConfigValue()
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
					Toggle(isOn: $ledState) {
						Label("LED State", systemImage: ledState ? "lightbulb.led.fill" : "lightbulb.led")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.hidden)
					Text("The state of the LED (on/off)")
						.font(.caption)
						.foregroundStyle(.gray)
					HStack {
						Image(systemName: "eyedropper")
							.foregroundColor(.accentColor)
						ColorPicker("Color", selection: $color, supportsOpacity: false)
							.padding(5)
					}
					HStack {
						Image(systemName: "directcurrent")
							.foregroundColor(.accentColor)
						Stepper("Current: \(current)", value: $current, in: 0...31, step: 1)
							.padding(5)
					}
					.onChange(of: color, initial: true) {
						components = color.resolve(in: environment)
						hasChanges = true
					}
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.ambientLightingConfig == nil)
			Button {
				isPresentingSaveConfirm = true
			} label: {
				Label("save", systemImage: "square.and.arrow.down")
			}
			.disabled(self.bleManager.connectedPeripheral == nil || !hasChanges)
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				"are.you.sure",
				isPresented: $isPresentingSaveConfirm,
				titleVisibility: .visible
			) {
				let nodeName = node?.user?.longName ?? "unknown".localized
				let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
				Button(buttonText) {

				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if connectedNode != nil {
						var al = ModuleConfig.AmbientLightingConfig()
						al.ledState = ledState
						al.current = UInt32(current)
						if let components {
							al.red = UInt32(components.red * 255)
							al.green = UInt32(components.green * 255)
							al.blue = UInt32(components.blue * 255)
						}

						let adminMessageId =  bleManager.saveAmbientLightingModuleConfig(config: al, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
						if adminMessageId > 0 {
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
							goBack()
						}
					}
				}
			}
			message: {
				Text("config.save.confirm")
			}
			.navigationTitle("ambient.lighting.config")
			.navigationBarItems(trailing:
				ZStack {
					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
			})
			.onAppear {
				if self.bleManager.context == nil {
					self.bleManager.context = context
				}
				setAmbientLightingConfigValue()
				// Need to request a Ambient Lighting Config from the remote node before allowing changes
				if bleManager.connectedPeripheral != nil && node?.ambientLightingConfig == nil {
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if node != nil && connectedNode != nil {
						_ = bleManager.requestAmbientLightingConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					}
				}
			}
			.onChange(of: ledState) { newLedState in
				if node != nil && node!.ambientLightingConfig != nil {
					if newLedState != node!.ambientLightingConfig!.ledState { hasChanges = true }
				}
			}
		}
	}
	func setAmbientLightingConfigValue() {
		self.ledState = node?.ambientLightingConfig?.ledState ?? false
		self.current = Int(node?.ambientLightingConfig?.current ?? 10)
		let red = Double(node?.ambientLightingConfig?.red ?? 255)
		let green = Double(node?.ambientLightingConfig?.green ?? 255)
		let blue = Double(node?.ambientLightingConfig?.blue ?? 255)
		color = Color(red: red / 255.0, green: green / 255.0, blue: blue / 255.0)
		self.hasChanges = false
	}
}
