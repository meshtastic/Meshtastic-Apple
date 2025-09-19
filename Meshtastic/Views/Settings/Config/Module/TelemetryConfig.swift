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
	@State var deviceUpdateInterval = 0
	@State var environmentUpdateInterval = 0
	@State var environmentMeasurementEnabled = false
	@State var environmentScreenEnabled = false
	@State var environmentDisplayFahrenheit = false
	@State var powerMeasurementEnabled = false
	@State var powerUpdateInterval = 0
	@State var powerScreenEnabled = false
	
	@State var broadcastDeviceMetrics: Bool = true

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Telemetry", config: \.telemetryConfig, node: node, onAppear: setTelemetryValues)

				Section(header: Text("Update Interval")) {
					Toggle(isOn: $broadcastDeviceMetrics) {
						Label("Broadcast Device Metrics", systemImage: "minus.plus.batteryblock.fill")
						}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					if broadcastDeviceMetrics {
						Picker("Device Metrics", selection: $deviceUpdateInterval ) {
							ForEach(UpdateIntervals.allCases) { ui in
								if ui.rawValue >= 900 {
									Text(ui.description)
								}
							}
						}
						.pickerStyle(DefaultPickerStyle())
						.listRowSeparator(.hidden)
						Text("How often device metrics are sent out over the mesh. Default is 30 minutes.")
							.foregroundColor(.gray)
							.font(.callout)
							.listRowSeparator(.visible)
					}
					if environmentMeasurementEnabled {
						Picker("Environment Metrics", selection: $environmentUpdateInterval ) {
							ForEach(UpdateIntervals.allCases) { ui in
								if ui.rawValue >= 900 {
									Text(ui.description)
								}
							}
						}
						.pickerStyle(DefaultPickerStyle())
						.listRowSeparator(.hidden)
						Text("How often environment metrics are sent out over the mesh. Default is 30 minutes.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}
				Section(header: Text("Sensor Options")) {
					Text("Supported I2C Connected sensors will be detected automatically, sensors are BMP280, BME280, BME680, MCP9808, INA219, INA260, LPS22 and SHTC3.")
						.foregroundColor(.gray)
						.font(.callout)
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
				Section(header: Text("Power Options")) {
					Toggle(isOn: $powerMeasurementEnabled) {
						Label("Enabled", systemImage: "bolt")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)
					if powerMeasurementEnabled {
						Picker("Power Metrics", selection: $powerUpdateInterval ) {
							ForEach(UpdateIntervals.allCases) { ui in
								if ui.rawValue >= 900 {
									Text(ui.description)
								}
							}
						}
						.pickerStyle(DefaultPickerStyle())
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

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
				let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? -1, context: context)
				if connectedNode != nil {
					var tc = ModuleConfig.TelemetryConfig()
					if broadcastDeviceMetrics {
						tc.deviceUpdateInterval = UInt32(deviceUpdateInterval)
					} else {
						tc.deviceUpdateInterval = UInt32.max
					}
					tc.environmentUpdateInterval = UInt32(environmentUpdateInterval)
					tc.environmentMeasurementEnabled = environmentMeasurementEnabled
					tc.environmentScreenEnabled = environmentScreenEnabled
					tc.environmentDisplayFahrenheit = environmentDisplayFahrenheit
					tc.powerMeasurementEnabled = powerMeasurementEnabled
					tc.powerUpdateInterval = UInt32(powerUpdateInterval)
					tc.powerScreenEnabled = powerScreenEnabled

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
			.onChange(of: broadcastDeviceMetrics) { _, newBroadcastDeviceMetrics in
				if !newBroadcastDeviceMetrics && deviceUpdateInterval != UInt32.max {
					hasChanges = true
				}
			}
			.onChange(of: deviceUpdateInterval) { _, newDeviceInterval in
				if newDeviceInterval != node?.telemetryConfig?.deviceUpdateInterval ?? -1 { hasChanges = true }
				if deviceUpdateInterval == UInt32.max {
					self.broadcastDeviceMetrics = false
				}			}
			.onChange(of: environmentUpdateInterval) { _, newEnvInterval in
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
			.onChange(of: powerUpdateInterval) { _, newPowerUpdateInterval in
				if newPowerUpdateInterval != node?.telemetryConfig?.powerUpdateInterval ?? -1 { hasChanges = true	}
			}
			.onChange(of: powerScreenEnabled) { _, newPowerScreenEnabled in
				if newPowerScreenEnabled != node?.telemetryConfig?.powerScreenEnabled { hasChanges = true	}
			}
		}
	}
	func setTelemetryValues() {
		self.deviceUpdateInterval = Int(node?.telemetryConfig?.deviceUpdateInterval ?? 1800)
		self.environmentUpdateInterval = Int(node?.telemetryConfig?.environmentUpdateInterval ?? 1800)
		self.environmentMeasurementEnabled = node?.telemetryConfig?.environmentMeasurementEnabled ?? false
		self.environmentScreenEnabled = node?.telemetryConfig?.environmentScreenEnabled ?? false
		self.environmentDisplayFahrenheit = node?.telemetryConfig?.environmentDisplayFahrenheit ?? false
		self.powerMeasurementEnabled = node?.telemetryConfig?.powerMeasurementEnabled ?? false
		self.powerUpdateInterval = Int(node?.telemetryConfig?.powerUpdateInterval ?? 1800)
		self.powerScreenEnabled = node?.telemetryConfig?.powerScreenEnabled ?? false
		self.hasChanges = false

		if self.deviceUpdateInterval == Int32.max {
			self.broadcastDeviceMetrics = false
			self.deviceUpdateInterval = 1800
		}
	}
}
