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
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var ledState: Bool = false
	@State var current = 0
	@State private var color = Color(red: 51, green: 199, blue: 88) // Color(.sRGB, red: 0.98, green: 0.9, blue: 0.2)
	@State private var components: ColorComponentsCompat?
	var body: some View {
		Form {
			ConfigHeader(title: "Ambient Lighting", config: \.ambientLightingConfig, node: node, onAppear: setAmbientLightingConfigValue)
			
			Section(header: Text("Options")) {
				
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
		.disabled(!self.accessoryManager.isConnected || node?.ambientLightingConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					guard let deviceNum = accessoryManager.activeDeviceNum else {
						return
					}
					let connectedNode = getNodeInfo(id: deviceNum, context: context)
					if connectedNode != nil {
						var al = ModuleConfig.AmbientLightingConfig()
						al.ledState = ledState
						al.current = UInt32(current)
						components = color.resolvedComponents(in: environment)
						if let components {
							al.red = UInt32(components.red * 255)
							al.green = UInt32(components.green * 255)
							al.blue = UInt32(components.blue * 255)
						}
						
						Task {
							do {
								_ = try await accessoryManager.saveAmbientLightingModuleConfig(config: al, fromUser: connectedNode!.user!, toUser: node!.user!)
								Task { @MainActor in
									hasChanges = false
									goBack()
								}
							} catch {
								Logger.mesh.warning("Unable to send ambient lighting module config")
							}
						}
					}
				}
			}}
		.navigationTitle("Ambient Lighting Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		)
		.onFirstAppear {
			// Need to request a Ambient Lighting Config from the remote node before allowing changes
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				let connectedNode = getNodeInfo(id: deviceNum, context: context)
				if let connectedNode {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.ambientLightingConfig == nil {
								Task {
									do {
										Logger.mesh.info("⚙️ Empty or expired ambient lighting module config requesting via PKI admin")
										try await accessoryManager.requestAmbientLightingConfig(fromUser: connectedNode.user!, toUser: node.user!)
									} catch {
										Logger.mesh.info("🚨 Unable to send  ambient lighting config request")
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
		.backport.onChange(of: ledState) { _, newLedState in
			if newLedState != node?.ambientLightingConfig?.ledState { hasChanges = true }
		}
		.backport.onChange(of: current) { _, newCurrent in
			if newCurrent != node?.ambientLightingConfig?.current ?? 10 { hasChanges = true }
		}
		.backport.onChange(of: color) { oldColor, newColor in
			if oldColor != newColor { hasChanges = true }
		}
	}
	func setAmbientLightingConfigValue() {
		self.ledState = node?.ambientLightingConfig?.ledState ?? false
		self.current = Int(node?.ambientLightingConfig?.current ?? 0)
		let red = Double(node?.ambientLightingConfig?.red ?? 255)
		let green = Double(node?.ambientLightingConfig?.green ?? 255)
		let blue = Double(node?.ambientLightingConfig?.blue ?? 255)
		color = Color(red: red / 255.0, green: green / 255.0, blue: blue / 255.0)
		self.hasChanges = false
	}
}
