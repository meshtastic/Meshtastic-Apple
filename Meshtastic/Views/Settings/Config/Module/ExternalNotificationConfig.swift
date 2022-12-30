//
//  External Notification Config.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
import SwiftUI

enum OutputIntervals: Int, CaseIterable, Identifiable {
	
	case unset = 0
	case oneSecond = 1000
	case twoSeconds = 2000
	case threeSeconds = 3000
	case fourSeconds = 4000
	case fiveSeconds = 5000
	case tenSeconds = 10000
	case fifteenSeconds = 15000
	case thirtySeconds = 30000
	case oneMinute = 60000
	
	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
				
			case .unset:
				return "Unset"
			case .oneSecond:
				return "One Second"
			case .twoSeconds:
				return "Two Seconds"
			case .threeSeconds:
				return "Three Seconds"
			case .fourSeconds:
				return "Four Seconds"
			case .fiveSeconds:
				return "Five Seconds"
			case .tenSeconds:
				return "Ten Seconds"
			case .fifteenSeconds:
				return "Fifteen Seconds"
			case .thirtySeconds:
				return "Thirty Seconds"
			case .oneMinute:
				return "One Minute"
			}
		}
	}
}

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
			if !usePWM {
				Section(header: Text("Primary GPIO")) {
					Toggle(isOn: $active) {
						Label("Active", systemImage: "togglepower")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("If enabled, the 'output' Pin will be pulled active high, disabled means active low.")
						.font(.caption)
					Picker("Output pin GPIO", selection: $output) {
						ForEach(0..<40) {
							if $0 == 0 {
								Text("Unset")
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
						ForEach(0..<40) {
							if $0 == 0 {
								Text("Unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Picker("Output pin vibra GPIO", selection: $outputVibra) {
						ForEach(0..<40) {
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
		.disabled(bleManager.connectedPeripheral == nil)
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
			Button("Save External Notification Module Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
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
				let adminMessageId =  bleManager.saveExternalNotificationModuleConfig(config: enc, fromUser: node!.user!, toUser: node!.user!)
				if adminMessageId > 0{
					// Should show a saved successfully alert once I know that to be true
					// for now just disable the button after a successful save
					hasChanges = false
					goBack()
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
