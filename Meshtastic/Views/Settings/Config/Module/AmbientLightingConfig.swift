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
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	let node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var ledState: Bool = false
	@State var current = 0
	@State private var color = Color(red: 51, green: 199, blue: 88) // Color(.sRGB, red: 0.98, green: 0.9, blue: 0.2)
	@State private var components: Color.Resolved?
	var body: some View {
		Form {
			ConfigHeader(title: "Ambient Lighting", config: \.ambientLightingConfig, node: node, onAppear: setAmbientLightingConfigValue)
			
			Section(header: Text("Options")) {
				
				Toggle(isOn: $ledState) {
					Label("LED State", systemImage: ledState ? "lightbulb.led.fill" : "lightbulb.led")
					Text("The state of the LED (on/off)")
				}
				.tint(.accentColor)
				
				HStack {
					Image(systemName: "eyedropper")
						.foregroundColor(.accentColor)
						// Decorative icon; the ColorPicker carries the label for VoiceOver.
						.accessibilityHidden(true)
					ColorPicker("Color", selection: $color, supportsOpacity: false)
						.padding(5)
				}
				HStack {
					Image(systemName: "directcurrent")
						.foregroundColor(.accentColor)
						// Decorative icon; the Stepper carries the label for VoiceOver.
						.accessibilityHidden(true)
					Stepper("Current: \(current)", value: $current, in: 0...31, step: 1)
						.padding(5)
				}
			}
		}
		.disabled(!self.accessoryManager.isConnected || node?.ambientLightingConfig == nil)
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
					var al = ModuleConfig.AmbientLightingConfig()
					al.ledState = ledState
					al.current = UInt32(current)
					components = color.resolve(in: environment)
					if let components {
						al.red = UInt32(components.red * 255)
						al.green = UInt32(components.green * 255)
						al.blue = UInt32(components.blue * 255)
					}
					_ = try await accessoryManager.saveAmbientLightingModuleConfig(config: al, fromUser: fromUser, toUser: toUser)
				}
			}
			}}
		.navigationTitle("Ambient Lighting Config")
		.toolbar {
	ToolbarItem(placement: .topBarTrailing) {
		ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
	}
}
		.onFirstAppear {
			requestRemoteConfig(
				node: node,
				context: context,
				accessoryManager: accessoryManager,
				configIsNil: { $0.ambientLightingConfig == nil },
				request: accessoryManager.requestAmbientLightingConfig
			)
		}
		.onChange(of: ledState) { _, newLedState in
			if newLedState != node?.ambientLightingConfig?.ledState { hasChanges = true }
		}
		.onChange(of: current) { _, newCurrent in
			if newCurrent != node?.ambientLightingConfig?.current ?? 10 { hasChanges = true }
		}
		.onChange(of: color) { oldColor, newColor in
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

#Preview {
	AmbientLightingConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
