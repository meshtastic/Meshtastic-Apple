//
//  TelemetryConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import SwiftUI

enum SensorTypes: Int, CaseIterable, Identifiable {

	/// No external telemetry sensor explicitly set
	case notSet = 0

	/// High accuracy temperature, pressure, humidity
	case bme280 = 6

	/// High accuracy temperature, pressure, humidity, and air resistance
	case bme680 = 7

	/// Very high accuracy temperature
	case mcp9808 = 8

	/// Moderate accuracy temperature and humidity
	case shtc3 = 9

	/// Moderate accuracy current and voltage
	case ina260 = 10

	/// Moderate accuracy current and voltage
	case ina219 = 11

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			
			case .notSet:
				return "Not Set"
			case .bme280:
				return "BME280 - Temp, pressure & humidity"
			case .bme680:
				return "BME680 - Temp, pressure, humidity & air resistance"
			case .mcp9808:
				return "MCP9808 - Temperature"
			case .shtc3:
				return "SHTC3 - Temperature & humidity"
			case .ina260:
				return "INA260 - Current & voltage"
			case .ina219:
				return "INA219 - Current & voltage"
			}
		}
	}
	func protoEnumValue() -> TelemetrySensorType {
		
		switch self {
			

		case .notSet:
			return TelemetrySensorType.notSet
		case .bme280:
			return TelemetrySensorType.bme280
		case .bme680:
			return TelemetrySensorType.bme680
		case .mcp9808:
			return TelemetrySensorType.mcp9808
		case .shtc3:
			return TelemetrySensorType.shtc3
		case .ina260:
			return TelemetrySensorType.ina260
		case .ina219:
			return TelemetrySensorType.ina219
		}
	}
}

// Default of 0 is off
enum ErrorRecoveryIntervals: Int, CaseIterable, Identifiable {

	case off = 0
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .off:
				return "Unset"
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
			}
		}
	}
}

enum UpdateIntervals: Int, CaseIterable, Identifiable {

	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 0
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
	@State var environmentSensorType = 0
	@State var environmentScreenEnabled = false
	@State var environmentDisplayFahrenheit = false
	@State var environmentRecoveryInterval = 0
	@State var environmentReadErrorCountThreshold = 0
	
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
				
					Toggle(isOn: $environmentMeasurementEnabled) {

						Label("Enabled", systemImage: "chart.xyaxis.line")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Picker("Sensor", selection: $environmentSensorType ) {
						ForEach(SensorTypes.allCases) { st in
							Text(st.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Toggle(isOn: $environmentScreenEnabled) {

						Label("Show on device screen", systemImage: "display")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Toggle(isOn: $environmentDisplayFahrenheit) {

						Label("Display Fahrenheit", systemImage: "thermometer")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

				}
				
				Section(header: Text("Errors")) {
					
					Picker("Error Count Threshold", selection: $environmentReadErrorCountThreshold) {
						ForEach(0..<101) {
							
							if $0 == 0 {
								
								Text("Unset")
								
							} else if $0 % 5 == 0 {
								
								Text("\($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Sometimes sensor reads can fail. If this happens, we will retry a configurable number of attempts, each attempt will be delayed by the minimum required refresh rate for that sensor")
						.font(.caption)
					
					Picker("Error Recovery Interval", selection: $environmentRecoveryInterval ) {
						ForEach(ErrorRecoveryIntervals.allCases) { eri in
							Text(eri.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Text("Sometimes we can end up with more failures than our error count threshold. In this case, we will stop trying to read from the sensor for a while. Wait this long until trying to read from the sensor again")
						.font(.caption)
				}
			}
			
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
					tc.environmentSensorType = SensorTypes(rawValue: environmentSensorType)!.protoEnumValue()
					tc.environmentScreenEnabled = environmentScreenEnabled
					tc.environmentDisplayFahrenheit = environmentDisplayFahrenheit
					tc.environmentRecoveryInterval = UInt32(environmentRecoveryInterval)
					tc.environmentReadErrorCountThreshold = UInt32(environmentReadErrorCountThreshold)
					
					let adminMessageId = bleManager.saveTelemetryModuleConfig(config: tc, fromUser: node!.user!, toUser:  node!.user!, wantResponse: true)
					
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
					self.environmentSensorType = Int(node!.telemetryConfig?.environmentSensorType ?? 0)
					self.environmentScreenEnabled = node!.telemetryConfig?.environmentScreenEnabled ?? false
					self.environmentDisplayFahrenheit = node!.telemetryConfig?.environmentDisplayFahrenheit ?? false
					self.environmentRecoveryInterval = Int(node!.telemetryConfig?.environmentRecoveryInterval ?? 0)
					self.environmentReadErrorCountThreshold = Int(node!.telemetryConfig?.environmentReadErrorCountThreshold ?? 0)
					
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
			.onChange(of: environmentSensorType) { newEnvSensorType in
				
				if node != nil && node!.telemetryConfig != nil {
				
					if newEnvSensorType != node!.telemetryConfig!.environmentSensorType { hasChanges = true	}
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
			.onChange(of: environmentRecoveryInterval) { newEnvRecoveryInterval in
				
				if node != nil && node!.telemetryConfig != nil {
				
					if newEnvRecoveryInterval != node!.telemetryConfig!.environmentRecoveryInterval { hasChanges = true	}
				}
			}
			.onChange(of: environmentReadErrorCountThreshold) { newEnvReadErrorCountThreshold in
				
				if node != nil && node!.telemetryConfig != nil {
				
					if newEnvReadErrorCountThreshold != node!.telemetryConfig!.environmentReadErrorCountThreshold { hasChanges = true	}
				}
			}
			.navigationViewStyle(StackNavigationViewStyle())
		}
	}
}
