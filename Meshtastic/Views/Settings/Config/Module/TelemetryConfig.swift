//
//  TelemetryConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct TelemetryConfig: View {
	
	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	let node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State private var deviceUpdateInterval: UpdateInterval = UpdateInterval(from: 0)
	@State private var environmentUpdateInterval: UpdateInterval = UpdateInterval(from: 0)
	@State var environmentMeasurementEnabled = false
	@State var environmentScreenEnabled = false
	@State var environmentDisplayFahrenheit = false
	@State var powerMeasurementEnabled = false
	@State private var powerUpdateInterval: UpdateInterval = UpdateInterval(from: 0)
	@State var powerScreenEnabled = false
	@State var deviceTelemetryEnabled = false

	var body: some View {
		Form {
			ConfigHeader(title: "Telemetry", config: \.telemetryConfig, node: node, onAppear: setTelemetryValues)
			
			Section(header: Text("Device Options")) {
				if accessoryManager.checkIsVersionSupported(forVersion: "2.7.12") {
					Toggle(isOn: $deviceTelemetryEnabled) {
						Label("Broadcast Device Metrics", systemImage: "wifi")
						Text("Enable broadcasting device metrics to the mesh network. When disabled, metrics are only sent to connected clients.")
					}
					.tint(.accentColor)
					
					if deviceTelemetryEnabled {
						UpdateIntervalPicker(
							config: .broadcastShort,
							pickerLabel: "Device Metrics",
							selectedInterval: $deviceUpdateInterval
						)
						.listRowSeparator(.hidden)
						Text("How often device metrics are sent out over the mesh. Default is 30 minutes.")
							.foregroundColor(.gray)
							.font(.callout)
							.listRowSeparator(.visible)
					}
				} else {
					// Legacy behavior for older firmware
					UpdateIntervalPicker(
						config: .broadcastShort,
						pickerLabel: "Device Metrics",
						selectedInterval: $deviceUpdateInterval
					)
					.listRowSeparator(.hidden)
					Text("How often device metrics are sent out over the mesh. Default is 30 minutes.")
						.foregroundColor(.gray)
						.font(.callout)
						.listRowSeparator(.visible)
				}
			}
			Section(header: Text("Environment Sensor Options")) {
				Text("Supported I2C Connected sensors will be detected automatically, sensors are BMP280, BME280, BME680, MCP9808, INA219, INA260, LPS22 and SHTC3.")
					.foregroundColor(.gray)
					.font(.callout)
				
				Toggle(isOn: $environmentMeasurementEnabled) {
					Label("Environment Metrics Enabled", systemImage: "chart.xyaxis.line")
				}
				.tint(.accentColor)
				
				if environmentMeasurementEnabled {
					UpdateIntervalPicker(
						config: .broadcastShort,
						pickerLabel: "Environment Metrics",
						selectedInterval: $environmentUpdateInterval
					)
					.listRowSeparator(.hidden)
					Text("How often environment metrics are sent out over the mesh. Default is 30 minutes.")
						.foregroundColor(.gray)
						.font(.callout)
						.listRowSeparator(.visible)
					
					Toggle(isOn: $environmentScreenEnabled) {
						Label("Show on device screen", systemImage: "display")
					}
					.tint(.accentColor)
					
					Toggle(isOn: $environmentDisplayFahrenheit) {
						Label("Display Fahrenheit", systemImage: "thermometer")
					}
					.tint(.accentColor)
				}
			}
			Section(header: Text("Power Sensor Options")) {
				Toggle(isOn: $powerMeasurementEnabled) {
					Label("Enabled", systemImage: "bolt")
				}
				.tint(.accentColor)
				
				if powerMeasurementEnabled {
					UpdateIntervalPicker(
						config: .broadcastShort,
						pickerLabel: "Power Metrics",
						selectedInterval: $powerUpdateInterval
					)
					.listRowSeparator(.hidden)
					Text("How often power metrics are sent out over the mesh. Default is 30 minutes.")
						.foregroundColor(.gray)
						.font(.callout)
						.listRowSeparator(.visible)
					Toggle(isOn: $powerScreenEnabled) {
						Label("Power Screen", systemImage: "tv")
					}
					.tint(.accentColor)
				}
			}
		}
		.disabled(!accessoryManager.isConnected || node?.telemetryConfig == nil)
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
					var tc = ModuleConfig.TelemetryConfig()
					tc.deviceUpdateInterval = UInt32(deviceUpdateInterval.intValue)
					tc.environmentUpdateInterval = UInt32(environmentUpdateInterval.intValue)
					tc.environmentMeasurementEnabled = environmentMeasurementEnabled
					tc.environmentScreenEnabled = environmentScreenEnabled
					tc.environmentDisplayFahrenheit = environmentDisplayFahrenheit
					tc.powerMeasurementEnabled = powerMeasurementEnabled
					tc.powerUpdateInterval = UInt32(powerUpdateInterval.intValue)
					tc.powerScreenEnabled = powerScreenEnabled
					if accessoryManager.checkIsVersionSupported(forVersion: "2.7.12") {
						tc.deviceTelemetryEnabled = deviceTelemetryEnabled
					}
					_ = try await accessoryManager.saveTelemetryModuleConfig(config: tc, fromUser: fromUser, toUser: toUser)
				}
			}
			}
		}
		.navigationTitle("Telemetry Config")
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
				configIsNil: { $0.telemetryConfig == nil },
				request: accessoryManager.requestTelemetryModuleConfig
			)
		}
		.onChange(of: deviceUpdateInterval.intValue) { _, newDeviceInterval in
			if newDeviceInterval != node?.telemetryConfig?.deviceUpdateInterval ?? -1 { hasChanges = true }
		}
		.onChange(of: environmentUpdateInterval.intValue) { _, newEnvInterval in
			if newEnvInterval != node?.telemetryConfig?.environmentUpdateInterval ?? -1 { hasChanges = true	}
		}
		.onChange(of: environmentMeasurementEnabled) { _, newEnvEnabled in
			if newEnvEnabled != node?.telemetryConfig?.environmentMeasurementEnabled { hasChanges = true }
		}
		.onChange(of: environmentScreenEnabled) { _, newEnvScreenEnabled in
			if newEnvScreenEnabled != node?.telemetryConfig?.environmentScreenEnabled { hasChanges = true	}
		}
		.onChange(of: environmentDisplayFahrenheit) { _, newEnvDisplayF in
			if newEnvDisplayF != node?.telemetryConfig?.environmentDisplayFahrenheit { hasChanges = true	}
		}
		.onChange(of: powerMeasurementEnabled) { _, newPowerMeasurementEnabled in
			if newPowerMeasurementEnabled != node?.telemetryConfig?.powerMeasurementEnabled { hasChanges = true	}
		}
		.onChange(of: powerUpdateInterval.intValue) { _, newPowerUpdateInterval in
			if newPowerUpdateInterval != node?.telemetryConfig?.powerUpdateInterval ?? -1 { hasChanges = true	}
		}
		.onChange(of: powerScreenEnabled) { _, newPowerScreenEnabled in
			if newPowerScreenEnabled != node?.telemetryConfig?.powerScreenEnabled { hasChanges = true	}
		}
		.onChange(of: deviceTelemetryEnabled) { _, newValue in
			let supportsToggle = accessoryManager.checkIsVersionSupported(forVersion: "2.7.12")
			if supportsToggle && newValue != node?.telemetryConfig?.deviceTelemetryEnabled {
				hasChanges = true
			}
		}
		
	}
	func setTelemetryValues() {
		let deviceInterval = Int(node?.telemetryConfig?.deviceUpdateInterval ?? 1800)
		self.deviceUpdateInterval = UpdateInterval(from: deviceInterval)
		self.environmentUpdateInterval = UpdateInterval(from: Int(node?.telemetryConfig?.environmentUpdateInterval ?? 1800))
		self.environmentMeasurementEnabled = node?.telemetryConfig?.environmentMeasurementEnabled ?? false
		self.environmentScreenEnabled = node?.telemetryConfig?.environmentScreenEnabled ?? false
		self.environmentDisplayFahrenheit = node?.telemetryConfig?.environmentDisplayFahrenheit ?? false
		self.powerMeasurementEnabled = node?.telemetryConfig?.powerMeasurementEnabled ?? false
		self.powerUpdateInterval = UpdateInterval(from: Int(node?.telemetryConfig?.powerUpdateInterval ?? 1800))
		self.powerScreenEnabled = node?.telemetryConfig?.powerScreenEnabled ?? false
		
		if accessoryManager.checkIsVersionSupported(forVersion: "2.7.12") {
			self.deviceTelemetryEnabled = node?.telemetryConfig?.deviceTelemetryEnabled ?? false
		} else {
			// Legacy behavior: if deviceUpdateInterval is Int32.max, telemetry is disabled
			self.deviceTelemetryEnabled = deviceInterval != Int(Int32.max)
		}
		
		self.hasChanges = false
	}
}

#Preview {
	TelemetryConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
