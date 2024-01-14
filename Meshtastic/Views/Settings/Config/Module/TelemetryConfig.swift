//
//  TelemetryConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import SwiftUI

struct TelemetryConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var deviceUpdateInterval = 0
	@State var environmentUpdateInterval = 0
	@State var environmentMeasurementEnabled = false
	@State var environmentScreenEnabled = false
	@State var environmentDisplayFahrenheit = false

	var body: some View {
		VStack {
			Form {
				if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					Text("There has been no response to a request for device metadata over the admin channel for this node.")
						.font(.callout)
						.foregroundColor(.orange)

				} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					// Let users know what is going on if they are using remote admin and don't have the config yet
					if node?.telemetryConfig == nil {
						Text("Telemetry config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
							.font(.callout)
							.foregroundColor(.orange)
					} else {
						Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
							.font(.title3)
							.onAppear {
								setTelemetryValues()
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
				Section(header: Text("update.interval")) {
					Picker("Device Metrics", selection: $deviceUpdateInterval ) {
						ForEach(UpdateIntervals.allCases) { ui in
							Text(ui.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("How often device metrics are sent out over the mesh. Default is 15 minutes.")
						.font(.caption)
					Picker("Sensor Metrics", selection: $environmentUpdateInterval ) {
						ForEach(UpdateIntervals.allCases) { ui in
							Text(ui.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("How often sensor metrics are sent out over the mesh. Default is 15 minutes.")
						.font(.caption)
				}
				Section(header: Text("Sensor Options")) {
					Text("Supported I2C Connected sensors will be detected automatically, sensors are BMP280, BME280, BME680, MCP9808, INA219, INA260, LPS22 and SHTC3.")
						.font(.caption)
					Toggle(isOn: $environmentMeasurementEnabled) {
						Label("enabled", systemImage: "chart.xyaxis.line")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Toggle(isOn: $environmentScreenEnabled) {
						Label("Show on device screen", systemImage: "display")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Toggle(isOn: $environmentDisplayFahrenheit) {
						Label("Display Fahrenheit", systemImage: "thermometer")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.telemetryConfig == nil)
			Button {
				isPresentingSaveConfirm = true
			} label: {
				Label("save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || !hasChanges || node!.telemetryConfig == nil)
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
						var tc = ModuleConfig.TelemetryConfig()
						tc.deviceUpdateInterval = UInt32(deviceUpdateInterval)
						tc.environmentUpdateInterval = UInt32(environmentUpdateInterval)
						tc.environmentMeasurementEnabled = environmentMeasurementEnabled
						tc.environmentScreenEnabled = environmentScreenEnabled
						tc.environmentDisplayFahrenheit = environmentDisplayFahrenheit
						let adminMessageId = bleManager.saveTelemetryModuleConfig(config: tc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
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
			.navigationTitle("telemetry.config")
			.navigationBarItems(trailing:
				ZStack {
					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
			})
			.onAppear {
				if self.bleManager.context == nil {
					self.bleManager.context = context
				}
				setTelemetryValues()
				// Need to request a TelemetryModuleConfig from the remote node before allowing changes
				if bleManager.connectedPeripheral != nil && node?.telemetryConfig == nil {
					print("empty telemetry module config")
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if node != nil && connectedNode != nil {
						_ = bleManager.requestTelemetryModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					}
				}
			}
			.onChange(of: deviceUpdateInterval) { newDeviceInterval in
				if node != nil && node?.telemetryConfig != nil {
					if newDeviceInterval != node!.telemetryConfig!.deviceUpdateInterval { hasChanges = true	}
				}
			}
			.onChange(of: environmentUpdateInterval) { newEnvInterval in
				if node != nil && node?.telemetryConfig != nil {
					if newEnvInterval != node!.telemetryConfig!.environmentUpdateInterval { hasChanges = true	}
				}
			}
			.onChange(of: environmentMeasurementEnabled) { newEnvEnabled in
				if node != nil && node?.telemetryConfig != nil {
					if newEnvEnabled != node!.telemetryConfig!.environmentMeasurementEnabled { hasChanges = true	}
				}
			}
			.onChange(of: environmentScreenEnabled) { newEnvScreenEnabled in
				if node!.telemetryConfig != nil {
					if newEnvScreenEnabled != node!.telemetryConfig!.environmentScreenEnabled { hasChanges = true	}
				}
			}
			.onChange(of: environmentDisplayFahrenheit) { newEnvDisplayF in
				if node != nil && node?.telemetryConfig != nil {
					if newEnvDisplayF != node!.telemetryConfig!.environmentDisplayFahrenheit { hasChanges = true	}
				}
			}
		}
	}
	func setTelemetryValues() {
		self.deviceUpdateInterval = Int(node?.telemetryConfig?.deviceUpdateInterval ?? 0)
		self.environmentUpdateInterval = Int(node?.telemetryConfig?.environmentUpdateInterval ?? 0)
		self.environmentMeasurementEnabled = node?.telemetryConfig?.environmentMeasurementEnabled ?? false
		self.environmentScreenEnabled = node?.telemetryConfig?.environmentScreenEnabled ?? false
		self.environmentDisplayFahrenheit = node?.telemetryConfig?.environmentDisplayFahrenheit ?? false
		self.hasChanges = false
	}
}
