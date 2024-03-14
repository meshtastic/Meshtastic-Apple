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
	@State var powerMeasurementEnabled = false
	@State var powerUpdateInterval = 0
	@State var powerScreenEnabled = false
	

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Telemetry", config: \.telemetryConfig, node: node, onAppear: setTelemetryValues)
				
				Section(header: Text("update.interval")) {
					Picker("Device Metrics", selection: $deviceUpdateInterval ) {
						ForEach(UpdateIntervals.allCases) { ui in
							if ui.rawValue >= 900 {
								Text(ui.description)
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.hidden)
					Text("How often device metrics are sent out over the mesh. Default is 15 minutes.")
						.foregroundColor(.gray)
						.font(.callout)
						.listRowSeparator(.visible)
					Picker("Sensor Metrics", selection: $environmentUpdateInterval ) {
						ForEach(UpdateIntervals.allCases) { ui in
							if ui.rawValue >= 900 {
								Text(ui.description)
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.hidden)
					Text("How often sensor metrics are sent out over the mesh. Default is 15 minutes.")
						.foregroundColor(.gray)
						.font(.callout)
				}
				Section(header: Text("Sensor Options")) {
					Text("Supported I2C Connected sensors will be detected automatically, sensors are BMP280, BME280, BME680, MCP9808, INA219, INA260, LPS22 and SHTC3.")
						.foregroundColor(.gray)
						.font(.callout)
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
				Section(header: Text("Power Options")) {
					Toggle(isOn: $powerMeasurementEnabled) {
						Label("enabled", systemImage: "bolt")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)
					Picker("Power Metrics", selection: $powerUpdateInterval ) {
						ForEach(UpdateIntervals.allCases) { ui in
							if ui.rawValue >= 900 {
								Text(ui.description)
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.listRowSeparator(.hidden)
					Text("How often power metrics are sent out over the mesh. Default is 15 minutes.")
						.foregroundColor(.gray)
						.font(.callout)
					.listRowSeparator(.visible)
					Toggle(isOn: $powerScreenEnabled) {
						Label("Power Screen", systemImage: "tv")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.telemetryConfig == nil)

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
				if connectedNode != nil {
					var tc = ModuleConfig.TelemetryConfig()
					tc.deviceUpdateInterval = UInt32(deviceUpdateInterval)
					tc.environmentUpdateInterval = UInt32(environmentUpdateInterval)
					tc.environmentMeasurementEnabled = environmentMeasurementEnabled
					tc.environmentScreenEnabled = environmentScreenEnabled
					tc.environmentDisplayFahrenheit = environmentDisplayFahrenheit
					tc.powerMeasurementEnabled = powerMeasurementEnabled
					tc.powerUpdateInterval = UInt32(powerUpdateInterval)
					tc.powerScreenEnabled = powerScreenEnabled
					let adminMessageId = bleManager.saveTelemetryModuleConfig(config: tc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
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
			.onChange(of: powerMeasurementEnabled) { newPowerMeasurementEnabled in
				if node != nil && node?.telemetryConfig != nil {
					if newPowerMeasurementEnabled != node!.telemetryConfig!.powerMeasurementEnabled { hasChanges = true	}
				}
			}
			.onChange(of: powerUpdateInterval) { newPowerUpdateInterval in
				if node != nil && node?.telemetryConfig != nil {
					if newPowerUpdateInterval != node!.telemetryConfig!.powerUpdateInterval { hasChanges = true	}
				}
			}		
			.onChange(of: powerScreenEnabled) { newPowerScreenEnabled in
				if node != nil && node?.telemetryConfig != nil {
					if newPowerScreenEnabled != node!.telemetryConfig!.powerScreenEnabled { hasChanges = true	}
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
		self.powerMeasurementEnabled = node?.telemetryConfig?.powerMeasurementEnabled ?? false
		self.powerUpdateInterval = Int(node?.telemetryConfig?.powerUpdateInterval ?? 0)
		self.powerScreenEnabled = node?.telemetryConfig?.powerScreenEnabled ?? false
		self.hasChanges = false
	}
}
