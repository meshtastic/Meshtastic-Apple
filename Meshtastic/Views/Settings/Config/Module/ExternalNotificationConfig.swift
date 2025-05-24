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
	@EnvironmentObject var bleManager: BLEManager
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
	@State var nagTimeout = 0
	@State var useI2SAsBuzzer = false

	var body: some View {
		VStack {
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
				Section(header: Text("Advanced GPIO Options")) {
					Section(header: Text("Primary GPIO")
						.font(.caption)
						.foregroundColor(.gray)
						.textCase(.uppercase)) {
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

							Picker("Nag timeout", selection: $nagTimeout ) {
								ForEach(NagIntervals.allCases) { oi in
									Text(oi.description)
								}
							}
							.pickerStyle(DefaultPickerStyle())
							.listRowSeparator(.hidden)
							Text("Specifies how long the monitored GPIO should output.")
								.foregroundColor(.gray)
								.font(.callout)
						}

					Section(header: Text("Optional GPIO")
						.font(.caption)
						.foregroundColor(.gray)
						.textCase(.uppercase)) {
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
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.externalNotificationConfig == nil)
		}

		SaveConfigButton(node: node, hasChanges: $hasChanges) {
			let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
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
				enc.nagTimeout = UInt32(nagTimeout)
				enc.outputBuzzer = UInt32(outputBuzzer)
				enc.outputVibra = UInt32(outputVibra)
				enc.outputMs = UInt32(outputMilliseconds)
				enc.usePwm = usePWM
				enc.useI2SAsBuzzer = useI2SAsBuzzer
				let adminMessageId =  bleManager.saveExternalNotificationModuleConfig(config: enc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				if adminMessageId > 0 {
					// Should show a saved successfully alert once I know that to be true
					// for now just disable the button after a successful save
					hasChanges = false
					goBack()
				}
			}
		}
		.navigationTitle("External Notification Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: bleManager.connectedPeripheral?.shortName ?? "?"
				)
			}
		)
		.onFirstAppear {
			// Need to request a ExternalNotificationModuleConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration && node.num != connectedNode.num {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.externalNotificationConfig == nil {
								Logger.mesh.info("⚙️ Empty or expired external notificaiton module config requesting via PKI admin")
								_ = bleManager.requestExternalNotificationModuleConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							/// Legacy Administration
							Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
						}
					}
				}
			}
		}
		.onChange(of: enabled) { _, newEnabled in
			if newEnabled != node?.externalNotificationConfig?.enabled { hasChanges = true }
		}
		.onChange(of: alertBell) { _, newAlertBell in
			if newAlertBell != node?.externalNotificationConfig?.alertBell { hasChanges = true }
		}
		.onChange(of: alertBellBuzzer) { _, newAlertBellBuzzer in
			if newAlertBellBuzzer != node?.externalNotificationConfig?.alertBellBuzzer { hasChanges = true }
		}
		.onChange(of: alertBellVibra) { _, newAlertBellVibra in
			if newAlertBellVibra != node?.externalNotificationConfig?.alertBellVibra { hasChanges = true }
		}
		.onChange(of: alertMessage) { _, newAlertMessage in
			if newAlertMessage != node?.externalNotificationConfig?.alertMessage { hasChanges = true }
		}
		.onChange(of: alertMessageBuzzer) { _, newAlertMessageBuzzer in
			if newAlertMessageBuzzer != node?.externalNotificationConfig?.alertMessageBuzzer { hasChanges = true }
		}
		.onChange(of: alertMessageVibra) { _, newAlertMessageVibra in
			if newAlertMessageVibra != node?.externalNotificationConfig?.alertMessageVibra { hasChanges = true }
		}
		.onChange(of: active) { _, newActive in
			if newActive != node?.externalNotificationConfig?.active { hasChanges = true }
		}
		.onChange(of: output) { _, newOutput in
			if newOutput != node?.externalNotificationConfig?.output ?? -1 { hasChanges = true }
		}
		.onChange(of: output) { _, newOutputBuzzer in
			if newOutputBuzzer != node?.externalNotificationConfig?.outputBuzzer ?? -1 { hasChanges = true }
		}
		.onChange(of: output) { _, newOutputVibra in
			if newOutputVibra != node?.externalNotificationConfig?.outputVibra ?? -1 { hasChanges = true }
		}
		.onChange(of: outputMilliseconds) { _, newOutputMs in
			if newOutputMs != node?.externalNotificationConfig?.outputMilliseconds ?? -1 { hasChanges = true }
		}
		.onChange(of: usePWM) { _, newPWM in
			if newPWM != node?.externalNotificationConfig?.usePWM { hasChanges = true }
		}
		.onChange(of: nagTimeout) { _, newNagTimeout in
			if newNagTimeout != node?.externalNotificationConfig?.nagTimeout ?? -1 { hasChanges = true }
		}
		.onChange(of: useI2SAsBuzzer) { _, newUseI2SAsBuzzer in
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
		self.nagTimeout = Int(node?.externalNotificationConfig?.nagTimeout ?? 0)
		self.usePWM = node?.externalNotificationConfig?.usePWM ?? false
		self.useI2SAsBuzzer = node?.externalNotificationConfig?.useI2SAsBuzzer ?? false
		self.hasChanges = false
	}
}
