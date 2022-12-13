//
//  RangeTestConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import SwiftUI

// Default of 0 is off
enum SenderIntervals: Int, CaseIterable, Identifiable {

	case off = 0
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800


	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .off:
				return "Off"
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
			}
		}
	}
}

struct RangeTestConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var enabled = false
	@State var sender = 0
	@State var save = false
	
	var body: some View {
		VStack {
			Form {
				Section(header: Text("options")) {
					Toggle(isOn: $enabled) {

						Label("enabled", systemImage: "figure.walk")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Picker("Sender Interval", selection: $sender ) {
						ForEach(SenderIntervals.allCases) { sci in
							Text(sci.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("This device will send out range test messages on the selected interval.")
						.font(.caption)
					Toggle(isOn: $save) {
						Label("save", systemImage: "square.and.arrow.down.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.disabled(!(node != nil && node!.myInfo?.hasWifi ?? false))
					Text("Saves a CSV with the range test message details, currently only available on ESP32 devices with a web server.")
						.font(.caption)
				}
			}
			.disabled(!(node != nil && node!.myInfo?.hasWifi ?? false))
			Button {
				isPresentingSaveConfirm = true
			} label: {
				Label("save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || !hasChanges || !(node?.myInfo?.hasWifi ?? false))
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				"are.you.sure",
				isPresented: $isPresentingSaveConfirm,
				titleVisibility: .visible
			) {
				Button("Save Range Test Module Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
				var rtc = ModuleConfig.RangeTestConfig()
					rtc.enabled = enabled
					rtc.save = save
					rtc.sender = UInt32(sender)
					let adminMessageId =  bleManager.saveRangeTestModuleConfig(config: rtc, fromUser: node!.user!, toUser: node!.user!)
					if adminMessageId > 0 {
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						goBack()
					}
				}
			}
			.navigationTitle("range.test.config")
			.navigationBarItems(trailing:
				ZStack {
					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
			})
			.onAppear {
				self.bleManager.context = context
				self.enabled = node?.rangeTestConfig?.enabled ?? false
				self.save = node?.rangeTestConfig?.save ?? false
				self.sender = Int(node?.rangeTestConfig?.sender ?? 0)
				self.hasChanges = false
			}
			.onChange(of: enabled) { newEnabled in
				if node != nil && node!.rangeTestConfig != nil {
					if newEnabled != node!.rangeTestConfig!.enabled { hasChanges = true }
				}
			}
			.onChange(of: save) { newSave in
				if node != nil && node!.rangeTestConfig != nil {
					if newSave != node!.rangeTestConfig!.save { hasChanges = true }
				}
			}
			.onChange(of: sender) { newSender in
				if node != nil && node!.rangeTestConfig != nil {
					if newSender != node!.rangeTestConfig!.sender { hasChanges = true }
				}
			}
		}
	}
}
