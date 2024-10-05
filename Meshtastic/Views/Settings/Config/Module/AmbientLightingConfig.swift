//
//  AmbientLightingConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/26/23
//
import MeshtasticProtobufs
import SwiftUI
import OSLog

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
				ConfigHeader(title: "Ambient Lighting", config: \.ambientLightingConfig, node: node, onAppear: setAmbientLightingConfigValue)

				Section(header: Text("options")) {

					Toggle(isOn: $ledState) {
						Label("LED State", systemImage: ledState ? "lightbulb.led.fill" : "lightbulb.led")
						Text("The state of the LED (on/off)")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

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
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.ambientLightingConfig == nil)

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
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
			.navigationTitle("ambient.lighting.config")
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
				// Need to request a Ambient Lighting Config from the remote node before allowing changes
				if let connectedPeripheral = bleManager.connectedPeripheral, let node {
					Logger.mesh.info("empty ambient lighting config")
					let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
					if let connectedNode {
						if node.num != connectedNode.num {
							if UserDefaults.enableAdministration {
								/// 2.5 Administration with session passkey
								let expiration = node.sessionExpiration ?? Date()
								if expiration < Date() || node.ambientLightingConfig == nil {
									_ = bleManager.requestAmbientLightingConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
								}
							} else {
								/// Legacy Administration
								_ = bleManager.requestAmbientLightingConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						}
					}
				}
			}
			.onChange(of: ledState) {
				if let val = node?.ambientLightingConfig?.ledState {
					hasChanges = $0 != val
				}
			}
			.onChange(of: current) {
				if let val = node?.ambientLightingConfig?.current {
					hasChanges = $0 != val
				}
			}
			.onChange(of: color) { c in
				if color != c {
					hasChanges = true
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
