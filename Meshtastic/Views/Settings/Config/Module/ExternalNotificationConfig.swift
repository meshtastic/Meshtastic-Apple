//
//  External Notification Config.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
import MeshtasticProtobufs
import OSLog
import SwiftUI

struct ExternalNotificationConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var enabled = false
	@State var alertBell = false
	@State var alertBellBuzzer = false
	@State var alertBellVibra = false
	@State var alertMessage = false
	@State var alertMessageBuzzer = false
	@State var alertMessageVibra = false
	@State var active = false
	@State var usePWM = false
	@State var output = 0
	@State var outputBuzzer = 0
	@State var outputVibra = 0
	@State var outputMilliseconds = 0
	@State private var nagTimeout: UpdateInterval = UpdateInterval(from: 0)
	@State var useI2SAsBuzzer = false
	
	var body: some View {
		Form {
			ConfigHeader(title: "External notification", config: \.externalNotificationConfig, node: node, onAppear: setExternalNotificationValues)
			
			Section(header: Text("Options")) {
				
				Toggle(isOn: $enabled) {
					Label("Enabled", systemImage: "megaphone")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				
				Toggle(isOn: $alertBell) {
					Label("Alert when receiving a bell", systemImage: "bell")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				
				Toggle(isOn: $alertMessage) {
					Label("Alert when receiving a message", systemImage: "message")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				
				Toggle(isOn: $usePWM) {
					Label("Use PWM Buzzer", systemImage: "light.beacon.max.fill")
					Text("Use a PWM output (like the RAK Buzzer) for tunes instead of an on/off output. This will ignore the output, output duration and active settings and use the device config buzzer GPIO option instead.")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				
				Toggle(isOn: $useI2SAsBuzzer) {
					Label("Use I2S As Buzzer", systemImage: "light.beacon.max.fill")
					Text("Enables devices with native I2S audio output to use the RTTTL over speaker like a buzzer. T-Watch S3 and T-Deck for example have this capability.")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
			}
			Section(header: Text("Primary GPIO")) {
				Toggle(isOn: $active) {
					Label("Active", systemImage: "togglepower")
					Text("If enabled, the 'output' Pin will be pulled active high, disabled means active low.")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				
				Picker("Output pin GPIO", selection: $output) {
					ForEach(0..<49) {
						if $0 == 0 {
							Text("Unset")
						} else {
							Text("Pin \($0)")
						}
					}
				}
				.pickerStyle(DefaultPickerStyle())
				.listRowSeparator(.visible)
				
				Picker("GPIO Output Duration", selection: $outputMilliseconds ) {
					ForEach(OutputIntervals.allCases) { oi in
						Text(oi.description)
					}
				}
				.pickerStyle(DefaultPickerStyle())
				.listRowSeparator(.hidden)
				Text("When using in GPIO mode, keep the output on for this long. ")
					.foregroundColor(.gray)
					.font(.callout)
					.listRowSeparator(.visible)
				UpdateIntervalPicker(
					config: .nagTimeout,
					pickerLabel: "Nag Timeout",
					selectedInterval: $nagTimeout
				)
				.listRowSeparator(.hidden)
			}
				
			Section(header: Text("Optional GPIO")) {
				Toggle(isOn: $alertBellBuzzer) {
					Label("Alert GPIO buzzer when receiving a bell", systemImage: "bell")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Toggle(isOn: $alertBellVibra) {
					Label("Alert GPIO vibra motor when receiving a bell", systemImage: "bell")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Toggle(isOn: $alertMessageBuzzer) {
					Label("Alert GPIO buzzer when receiving a message", systemImage: "message")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Toggle(isOn: $alertMessageBuzzer) {
					Label("Alert GPIO vibra motor when receiving a message", systemImage: "message")
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Picker("Output pin buzzer GPIO ", selection: $outputBuzzer) {
					ForEach(0..<49) {
						if $0 == 0 {
							Text("Unset")
						} else {
							Text("Pin \($0)")
						}
					}
				}
				.pickerStyle(DefaultPickerStyle())
				Picker("Output pin vibra GPIO", selection: $outputVibra) {
					ForEach(0..<49) {
						if $0 == 0 {
							Text("Unset")
						} else {
							Text("Pin \($0)")
						}
					}
				}
				.pickerStyle(DefaultPickerStyle())
			}
		}
		.disabled(!accessoryManager.isConnected || node?.externalNotificationConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? -1, context: context)
					if connectedNode != nil {
						var enc = ModuleConfig.ExternalNotificationConfig()
						enc.enabled = enabled
						enc.alertBell = alertBell
						enc.alertBellBuzzer = alertBellBuzzer
						enc.alertBellVibra = alertBellVibra
						enc.alertMessage = alertMessage
						enc.alertMessageBuzzer = alertMessageBuzzer
						enc.alertMessageVibra = alertMessageVibra
						enc.active = active
						enc.output = UInt32(output)
						enc.nagTimeout = UInt32(nagTimeout.intValue)
						enc.outputBuzzer = UInt32(outputBuzzer)
						enc.outputVibra = UInt32(outputVibra)
						enc.outputMs = UInt32(outputMilliseconds)
						enc.usePwm = usePWM
						enc.useI2SAsBuzzer = useI2SAsBuzzer
						Task {
							do {
								_ = try await accessoryManager.saveExternalNotificationModuleConfig(config: enc, fromUser: connectedNode!.user!, toUser: node!.user!)
								Task { @MainActor in
									hasChanges = false
									goBack()
								}
							} catch {
								Logger.mesh.error("Unable to save external notiication module config")
							}
						}
					}
				}
			}
		}
		.navigationTitle("External Notification Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					deviceConnected: accessoryManager.isConnected,
					name: accessoryManager.activeConnection?.device.shortName ?? "?"
				)
			}
		)
		.onFirstAppear {
			// Need to request a ExternalNotificationModuleConfig from the remote node before allowing changes
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				let connectedNode = getNodeInfo(id: deviceNum, context: context)
				if let connectedNode {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.externalNotificationConfig == nil {
								Task {
									do {
										Logger.mesh.info("⚙️ Empty or expired external notificaiton module config requesting via PKI admin")
										try await accessoryManager.requestExternalNotificationModuleConfig(fromUser: connectedNode.user!, toUser: node.user!)
									} catch {
										Logger.mesh.info("🚨 Unable to send external ntoification module config request")
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
		.backport.onChange(of: enabled) { _, newEnabled in
			if newEnabled != node?.externalNotificationConfig?.enabled { hasChanges = true }
		}
		.backport.onChange(of: alertBell) { _, newAlertBell in
			if newAlertBell != node?.externalNotificationConfig?.alertBell { hasChanges = true }
		}
		.backport.onChange(of: alertBellBuzzer) { _, newAlertBellBuzzer in
			if newAlertBellBuzzer != node?.externalNotificationConfig?.alertBellBuzzer { hasChanges = true }
		}
		.backport.onChange(of: alertBellVibra) { _, newAlertBellVibra in
			if newAlertBellVibra != node?.externalNotificationConfig?.alertBellVibra { hasChanges = true }
		}
		.backport.onChange(of: alertMessage) { _, newAlertMessage in
			if newAlertMessage != node?.externalNotificationConfig?.alertMessage { hasChanges = true }
		}
		.backport.onChange(of: alertMessageBuzzer) { _, newAlertMessageBuzzer in
			if newAlertMessageBuzzer != node?.externalNotificationConfig?.alertMessageBuzzer { hasChanges = true }
		}
		.backport.onChange(of: alertMessageVibra) { _, newAlertMessageVibra in
			if newAlertMessageVibra != node?.externalNotificationConfig?.alertMessageVibra { hasChanges = true }
		}
		.backport.onChange(of: active) { _, newActive in
			if newActive != node?.externalNotificationConfig?.active { hasChanges = true }
		}
		.backport.onChange(of: output) { _, newOutput in
			if newOutput != node?.externalNotificationConfig?.output ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: output) { _, newOutputBuzzer in
			if newOutputBuzzer != node?.externalNotificationConfig?.outputBuzzer ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: output) { _, newOutputVibra in
			if newOutputVibra != node?.externalNotificationConfig?.outputVibra ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: outputMilliseconds) { _, newOutputMs in
			if newOutputMs != node?.externalNotificationConfig?.outputMilliseconds ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: usePWM) { _, newPWM in
			if newPWM != node?.externalNotificationConfig?.usePWM { hasChanges = true }
		}
		.backport.onChange(of: nagTimeout.intValue) { _, newNagTimeout in
			if newNagTimeout != node?.externalNotificationConfig?.nagTimeout ?? -1 { hasChanges = true }
		}
		.backport.onChange(of: useI2SAsBuzzer) { _, newUseI2SAsBuzzer in
			if newUseI2SAsBuzzer != node?.externalNotificationConfig?.useI2SAsBuzzer { hasChanges = true }
		}
	}
	func setExternalNotificationValues() {
		self.enabled = node?.externalNotificationConfig?.enabled ?? false
		self.alertBell = node?.externalNotificationConfig?.alertBell ?? false
		self.alertBellBuzzer = node?.externalNotificationConfig?.alertBellBuzzer ?? false
		self.alertBellVibra = node?.externalNotificationConfig?.alertBellVibra ?? false
		self.alertMessage = node?.externalNotificationConfig?.alertMessage ?? false
		self.alertMessageBuzzer = node?.externalNotificationConfig?.alertMessageBuzzer ?? false
		self.alertMessageVibra = node?.externalNotificationConfig?.alertMessageVibra ?? false
		self.active = node?.externalNotificationConfig?.active ?? false
		self.output = Int(node?.externalNotificationConfig?.output ?? 0)
		self.outputBuzzer = Int(node?.externalNotificationConfig?.outputBuzzer ?? 0)
		self.outputVibra = Int(node?.externalNotificationConfig?.outputVibra ?? 0)
		self.outputMilliseconds = Int(node?.externalNotificationConfig?.outputMilliseconds ?? 0)
		self.nagTimeout =  UpdateInterval(from: Int(node?.externalNotificationConfig?.nagTimeout ?? 0))
		self.usePWM = node?.externalNotificationConfig?.usePWM ?? false
		self.useI2SAsBuzzer = node?.externalNotificationConfig?.useI2SAsBuzzer ?? false
		self.hasChanges = false
	}
}

