//
//  TelemetryConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import SwiftUI

enum UpdateIntervals: Int, CaseIterable, Identifiable {

	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case twoHours = 7200
	case threeHours = 10800
	case fourHours = 14400
	case fiveHours = 18000
	case sixHours = 21600
	case twelveHours = 43200
	case eighteenHours = 64800
	case twentyFourHours = 86400

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .fifteenSeconds:
				return "Fifteen Seconds"
			case .thirtySeconds:
				return "Thirty Seconds"
			case .oneMinute:
				return "One Minute"
			case .fiveMinutes:
				return "Five Minutes"
			case .tenMinutes:
				return "Ten Minutes"
			case .fifteenMinutes:
				return "Fifteen Minutes"
			case .thirtyMinutes:
				return "Thirty Minutes"
			case .oneHour:
				return "One Hour"
			case .twoHours:
				return "Two Hours"
			case .threeHours:
				return "Three Hours"
			case .fourHours:
				return "Four Hours"
			case .fiveHours:
				return "Five Hours"
			case .sixHours:
				return "Six Hours"
			case .twelveHours:
				return "Twelve Hours"
			case .eighteenHours:
				return "Eighteen Hours"
			case .twentyFourHours:
				return "Twenty Four Hours"
			}
		}
	}
}

struct TelemetryConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges = false
	
	@State var deviceUpdateInterval = 0
	@State var environmentUpdateInterval = 0
	@State var environmentMeasurementEnabled = false
	@State var environmentScreenEnabled = false
	@State var environmentDisplayFahrenheit = false
	
	var body: some View {
		
		VStack {

			Form {
				
				Section(header: Text("Update Intervals")) {
					
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
					
					Text("Supported I2C Connected sensors will be detected automatically, sensors are BMP280, BME280, BME680, MCP9808, INA219 and INA260.")
						.font(.caption)
				
					Toggle(isOn: $environmentMeasurementEnabled) {

						Label("Enabled", systemImage: "chart.xyaxis.line")
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
			.disabled(bleManager.connectedPeripheral == nil)
			
			Button {
							
				isPresentingSaveConfirm = true
				
			} label: {
				
				Label("Save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || !hasChanges || node!.telemetryConfig == nil)
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				
				"Are you sure?",
				isPresented: $isPresentingSaveConfirm
			) {
				Button("Save Telemetry Module Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
						
					var tc = ModuleConfig.TelemetryConfig()
					tc.deviceUpdateInterval = UInt32(deviceUpdateInterval)
					tc.environmentUpdateInterval = UInt32(environmentUpdateInterval)
					tc.environmentMeasurementEnabled = environmentMeasurementEnabled
					tc.environmentScreenEnabled = environmentScreenEnabled
					tc.environmentDisplayFahrenheit = environmentDisplayFahrenheit
					
					let adminMessageId = bleManager.saveTelemetryModuleConfig(config: tc, fromUser: node!.user!, toUser:  node!.user!)
					
					if adminMessageId > 0 {
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						
					} else {
						
					}
				}
			}
			
			.navigationTitle("Telemetry Config")
			.navigationBarItems(trailing:

				ZStack {

				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
			})
			.onAppear {

				if self.initialLoad{
					
					self.bleManager.context = context
					self.deviceUpdateInterval = Int(node!.telemetryConfig?.deviceUpdateInterval ?? 0)
					self.environmentUpdateInterval = Int(node!.telemetryConfig?.environmentUpdateInterval ?? 0)
					self.environmentMeasurementEnabled = node!.telemetryConfig?.environmentMeasurementEnabled ?? false
					self.environmentScreenEnabled = node!.telemetryConfig?.environmentScreenEnabled ?? false
					self.environmentDisplayFahrenheit = node!.telemetryConfig?.environmentDisplayFahrenheit ?? false
					self.hasChanges = false
					self.initialLoad = false
				}
			}
			.onChange(of: deviceUpdateInterval) { newDeviceInterval in
				
				if node != nil && node!.telemetryConfig != nil {
				
					if newDeviceInterval != node!.telemetryConfig!.deviceUpdateInterval { hasChanges = true	}
				}
			}
			.onChange(of: environmentUpdateInterval) { newEnvInterval in
				
				if node != nil && node!.telemetryConfig != nil {
				
					if newEnvInterval != node!.telemetryConfig!.environmentUpdateInterval { hasChanges = true	}
				}
			}
			.onChange(of: environmentMeasurementEnabled) { newEnvEnabled in
				
				if node != nil && node!.telemetryConfig != nil {
				
					if newEnvEnabled != node!.telemetryConfig!.environmentMeasurementEnabled { hasChanges = true	}
				}
			}
			.onChange(of: environmentScreenEnabled) { newEnvScreenEnabled in
				
				if node!.telemetryConfig != nil {
				
					if newEnvScreenEnabled != node!.telemetryConfig!.environmentScreenEnabled { hasChanges = true	}
				}
			}
			.onChange(of: environmentDisplayFahrenheit) { newEnvDisplayF in
				
				if node != nil && node!.telemetryConfig != nil {
				
					if newEnvDisplayF != node!.telemetryConfig!.environmentDisplayFahrenheit { hasChanges = true	}
				}
			}
			.navigationViewStyle(StackNavigationViewStyle())
		}
	}
}
