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
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	
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
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
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
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				
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
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $environmentDisplayFahrenheit) {
						Label("Display Fahrenheit", systemImage: "thermometer")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
			}
			Section(header: Text("Power Sensor Options")) {
				Toggle(isOn: $powerMeasurementEnabled) {
					Label("Enabled", systemImage: "bolt")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				
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
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
			}
		}
		.disabled(!accessoryManager.isConnected || node?.telemetryConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? -1, context: context)
					if connectedNode != nil {
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
						
						Task {
							_ = try await accessoryManager.saveTelemetryModuleConfig(config: tc, fromUser: connectedNode!.user!, toUser: node!.user!)
							Task { @MainActor in
								// Should show a saved successfully alert once I know that to be true
								// for now just disable the button after a successful save
								hasChanges = false
								goBack()
							}
						}
					}
				}
			}
		}
		.navigationTitle("Telemetry Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
				
			}
		)
		.onFirstAppear {
			// Need to request a TelemetryModuleConfig from the remote node before allowing changes
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				let connectedNode = getNodeInfo(id: deviceNum, context: context)
				if let connectedNode {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration && node.num != deviceNum {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.telemetryConfig == nil {
								Task {
									do {
										Logger.mesh.info("⚙️ Empty or expired telemetry module config requesting via PKI admin")
										try await accessoryManager.requestTelemetryModuleConfig(fromUser: connectedNode.user!, toUser: node.user!)
									} catch {
										Logger.mesh.info("🚨 Telemetry module config request failed: \(error.localizedDescription)")
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
		.backport.onChange(of: deviceUpdateInterval.intValue) { _, newDeviceInterval in
			if newDeviceInterval != node?.telemetryConfig?.deviceUpdateInterval ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: environmentUpdateInterval.intValue) { _, newEnvInterval in
			if newEnvInterval != node?.telemetryConfig?.environmentUpdateInterval ?? -1 { hasChanges = true	}
		}
		.backport.onChange(of: environmentMeasurementEnabled) { _, newEnvEnabled in
			if newEnvEnabled != node?.telemetryConfig?.environmentMeasurementEnabled { hasChanges = true }
		}
		.backport.onChange(of: environmentScreenEnabled) { _, newEnvScreenEnabled in
			if newEnvScreenEnabled != node?.telemetryConfig?.environmentScreenEnabled { hasChanges = true	}
		}
		.backport.onChange(of: environmentDisplayFahrenheit) { _, newEnvDisplayF in
			if newEnvDisplayF != node?.telemetryConfig?.environmentDisplayFahrenheit { hasChanges = true	}
		}
		.backport.onChange(of: powerMeasurementEnabled) { _, newPowerMeasurementEnabled in
			if newPowerMeasurementEnabled != node?.telemetryConfig?.powerMeasurementEnabled { hasChanges = true	}
		}
		.backport.onChange(of: powerUpdateInterval.intValue) { _, newPowerUpdateInterval in
			if newPowerUpdateInterval != node?.telemetryConfig?.powerUpdateInterval ?? -1 { hasChanges = true	}
		}
		.backport.onChange(of: powerScreenEnabled) { _, newPowerScreenEnabled in
			if newPowerScreenEnabled != node?.telemetryConfig?.powerScreenEnabled { hasChanges = true	}
		}
		.backport.onChange(of: deviceTelemetryEnabled) { _, newDeviceTelemetryEnabled in
			if accessoryManager.checkIsVersionSupported(forVersion: "2.7.12") {
				if newDeviceTelemetryEnabled != node?.telemetryConfig?.deviceTelemetryEnabled { hasChanges = true }
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
