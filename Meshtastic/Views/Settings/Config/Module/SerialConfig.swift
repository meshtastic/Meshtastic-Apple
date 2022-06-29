//
//  SerialConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
import SwiftUI

enum SerialBaudRates: Int, CaseIterable, Identifiable {

	case baudDefault = 0
	case baud110 = 1
	case baud300 = 2
	case baud600 = 3
	case baud1200 = 4
	case baud2400 = 5
	case baud4800 = 6
	case baud9600 = 7
	case baud19200 = 8
	case baud38400 = 9
	case baud57600 = 10
	case baud115200 = 11
	case baud230400 = 12
	case baud460800 = 13
	case baud576000 = 14
	case baud921600 = 15

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {

			case .baudDefault:
				return "Unset"
			case .baud110:
				return "110 Baud"
			case .baud300:
				return "300 Baud"
			case .baud600:
				return "600 Baud"
			case .baud1200:
				return "1200 Baud"
			case .baud2400:
				return "2400 Baud"
			case .baud4800:
				return "4800 Baud"
			case .baud9600:
				return "9600 Baud"
			case .baud19200:
				return "19200 Baud"
			case .baud38400:
				return "38400 Baud"
			case .baud57600:
				return "57600 Baud"
			case .baud115200:
				return "115200 Baud"
			case .baud230400:
				return "230400 Baud"
			case .baud460800:
				return "460800 Baud"
			case .baud576000:
				return "576000 Baud"
			case .baud921600:
				return "921600 Baud"
			}
		}
	}
}

enum SerialModeTypes: Int, CaseIterable, Identifiable {

	case modeDefault = 0
	case modeSimple = 1
	case modeProto = 2

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .modeDefault:
				return "Default"
			case .modeSimple:
				return "Simple"
			case .modeProto:
				return "Protobufs"
			}
		}
	}
}

enum SerialTimeoutIntervals: Int, CaseIterable, Identifiable {

	case unset = 0
	case fiveSeconds = 5
	case tenSeconds = 10
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .unset:
				return "Unset"
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
			case .fiveMinutes:
				return "Five Minutes"

			}
		}
	}
}

struct SerialConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges = false
	
	@State var enabled = false
	@State var echo = false
	@State var rxd = 0
	@State var txd = 0
	@State var baudRate = 0
	@State var timeout = 0
	@State var mode = 0
	
	var body: some View {
		
		VStack {

			Form {
				
				Section(header: Text("Options")) {
				
					Toggle(isOn: $enabled) {

						Label("Enabled", systemImage: "terminal")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $echo) {

						Label("Echo", systemImage: "repeat")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("If set, any packets you send will be echoed back to your device.")
						.font(.caption)
					
					Picker("Baud Rate", selection: $baudRate ) {
						ForEach(SerialBaudRates.allCases) { sbr in
							Text(sbr.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Picker("Timeout", selection: $timeout ) {
						ForEach(SerialTimeoutIntervals.allCases) { sti in
							Text(sti.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("The amount of time to wait before we consider your packet as done.")
						.font(.caption)
					
					Picker("Mode", selection: $mode ) {
						ForEach(SerialModeTypes.allCases) { smt in
							Text(smt.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
				}
				Section(header: Text("GPIO")) {
					
					Picker("Receive data (rxd) GPIO pin", selection: $rxd) {
						ForEach(0..<40) {
							
							if $0 == 0 {
								
								Text("Unset")
								
							} else {
							
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())

					Picker("Transmit data (txd) GPIO pin", selection: $txd) {
						ForEach(0..<40) {
							
							if $0 == 0 {
								
								Text("Unset")
								
							} else {
							
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Set the GPIO pins for RXD and TXD.")
						.font(.caption)
				}
			}
			
			Button {
							
				isPresentingSaveConfirm = true
				
			} label: {
				
				Label("Save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				
				"Are you sure?",
				isPresented: $isPresentingSaveConfirm
			) {
				Button("Save Range Test Module Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
						
					var sc = ModuleConfig.SerialConfig()
					sc.enabled = enabled
					//sc.save = save
					//sc.sender = sender ? 1 : 0
					
					if bleManager.saveSerialModuleConfig(config: sc, destNum: bleManager.connectedPeripheral.num, wantResponse: false) {
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						
					} else {
						
					}
				}
			}
			
			.navigationTitle("Serial Config")
			.navigationBarItems(trailing:

				ZStack {

					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?????")
			})
			.onAppear {

				self.bleManager.context = context
			}
			.navigationViewStyle(StackNavigationViewStyle())
		}
	}
}
