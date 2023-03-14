//
//  External Notification Config.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
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

	var body: some View {

		Form {
			if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
				Text("There has been no response to a request for device metadata over the admin channel for this node.")
					.font(.callout)
					.foregroundColor(.orange)
				
			} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
				// Let users know what is going on if they are using remote admin and don't have the config yet
				if node?.externalNotificationConfig == nil  {
					Text("External notification config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
						.font(.callout)
						.foregroundColor(.orange)
				} else {
					Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
						.font(.title3)
				}
			} else if node != nil && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? 0{
				Text("Configuration for: \(node?.user?.longName ?? "Unknown")")
					.font(.title3)
			} else {
				Text("Please connect to a radio to configure settings.")
					.font(.callout)
					.foregroundColor(.orange)
			}
			Section(header: Text("options")) {
				Toggle(isOn: $enabled) {
					Label("enabled", systemImage: "megaphone")
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
				}
				.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				Text("Use a PWM output (like the RAK Buzzer) for tunes instead of an on/off output. This will ignore the output, output duration and active settings and use the device config buzzer GPIO option instead.")
					.font(.caption)
			}
			Section(header: Text("Advanced GPIO Options")) {
				Section(header: Text("Primary GPIO")
					.font(.caption)
					.foregroundColor(.gray)
					.textCase(.uppercase)) {
					Toggle(isOn: $active) {
						Label("Active", systemImage: "togglepower")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("If enabled, the 'output' Pin will be pulled active high, disabled means active low.")
						.font(.caption)
					Picker("Output pin GPIO", selection: $output) {
						ForEach(0..<40) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Picker("GPIO Output Duration", selection: $outputMilliseconds ) {
						ForEach(OutputIntervals.allCases) { oi in
							Text(oi.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("When using in GPIO mode, keep the output on for this long. ")
						.font(.caption)
					Picker("Nag timeout", selection: $nagTimeout ) {
						ForEach(OutputIntervals.allCases) { oi in
							Text(oi.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Specifies how long the monitored GPIO should output.")
						.font(.caption)
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
						ForEach(0..<40) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Picker("Output pin vibra GPIO", selection: $outputVibra) {
						ForEach(0..<40) {
							if $0 == 0 {
								Text("unset")
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
		Button {
			isPresentingSaveConfirm = true
		} label: {
			Label("save", systemImage: "square.and.arrow.down")
		}
		.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
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
				let nodeName = node?.user?.longName ?? NSLocalizedString("unknown", comment: "Unknown")
				let buttonText = String.localizedStringWithFormat(NSLocalizedString("save.config %@", comment: "Save Config for %@"), nodeName)
				Button(buttonText) {
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
					enc.outputBuzzer = UInt32(outputBuzzer)
					enc.outputVibra = UInt32(outputVibra)
					enc.outputMs = UInt32(outputMilliseconds)
					enc.usePwm = usePWM
					let adminMessageId =  bleManager.saveExternalNotificationModuleConfig(config: enc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
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
		.navigationTitle("external.notification.config")
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			self.bleManager.context = context
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
			self.hasChanges = false

			// Need to request a TelemetryModuleConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.externalNotificationConfig == nil {
				print("empty external notification module config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil {
					_ = bleManager.requestExternalNotificationModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: enabled) { newEnabled in
			if node != nil && node!.externalNotificationConfig != nil {
				if newEnabled != node!.externalNotificationConfig!.enabled { hasChanges = true }
			}
		}
		.onChange(of: alertBell) { newAlertBell in
			if node != nil && node!.externalNotificationConfig != nil {
				if newAlertBell != node!.externalNotificationConfig!.alertBell { hasChanges = true }
			}
		}
		.onChange(of: alertBellBuzzer) { newAlertBellBuzzer in
			if node != nil && node!.externalNotificationConfig != nil {
				if newAlertBellBuzzer != node!.externalNotificationConfig!.alertBellBuzzer { hasChanges = true }
			}
		}
		.onChange(of: alertBellVibra) { newAlertBellVibra in
			if node != nil && node!.externalNotificationConfig != nil {
				if newAlertBellVibra != node!.externalNotificationConfig!.alertBellVibra { hasChanges = true }
			}
		}
		.onChange(of: alertMessage) { newAlertMessage in
			if node != nil && node!.externalNotificationConfig != nil {
				if newAlertMessage != node!.externalNotificationConfig!.alertMessage { hasChanges = true }
			}
		}
		.onChange(of: alertMessageBuzzer) { newAlertMessageBuzzer in
			if node != nil && node!.externalNotificationConfig != nil {
				if newAlertMessageBuzzer != node!.externalNotificationConfig!.alertMessageBuzzer { hasChanges = true }
			}
		}
		.onChange(of: alertMessageVibra) { newAlertMessageVibra in
			if node != nil && node!.externalNotificationConfig != nil {
				if newAlertMessageVibra != node!.externalNotificationConfig!.alertMessageVibra { hasChanges = true }
			}
		}
		.onChange(of: active) { newActive in
			if node != nil && node!.externalNotificationConfig != nil {
				if newActive != node!.externalNotificationConfig!.active { hasChanges = true }
			}
		}
		.onChange(of: output) { newOutput in
			if node != nil && node!.externalNotificationConfig != nil {
				if newOutput != node!.externalNotificationConfig!.output { hasChanges = true }
			}
		}
		.onChange(of: output) { newOutputBuzzer in
			if node != nil && node!.externalNotificationConfig != nil {
				if newOutputBuzzer != node!.externalNotificationConfig!.outputBuzzer { hasChanges = true }
			}
		}
		.onChange(of: output) { newOutputVibra in
			if node != nil && node!.externalNotificationConfig != nil {
				if newOutputVibra != node!.externalNotificationConfig!.outputVibra { hasChanges = true }
			}
		}
		.onChange(of: outputMilliseconds) { newOutputMs in
			if node != nil && node!.externalNotificationConfig != nil {
				if newOutputMs != node!.externalNotificationConfig!.outputMilliseconds { hasChanges = true }
			}
		}
		.onChange(of: usePWM) { newUsePWM in
			if node != nil && node!.externalNotificationConfig != nil {
				if newUsePWM != node!.externalNotificationConfig!.usePWM { hasChanges = true }
			}
		}
		.onChange(of: nagTimeout) { newNagTimeout in
			if node != nil && node!.externalNotificationConfig != nil {
				if newNagTimeout != node!.externalNotificationConfig!.nagTimeout { hasChanges = true }
			}
		}
	}
}
