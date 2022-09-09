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
	
	func protoEnumValue() -> ModuleConfig.SerialConfig.Serial_Baud {
		
		switch self {
			
		case .baudDefault:
			return ModuleConfig.SerialConfig.Serial_Baud.baudDefault
		case .baud110:
			return ModuleConfig.SerialConfig.Serial_Baud.baud110
		case .baud300:
			return ModuleConfig.SerialConfig.Serial_Baud.baud300
		case .baud600:
			return ModuleConfig.SerialConfig.Serial_Baud.baud600
		case .baud1200:
			return ModuleConfig.SerialConfig.Serial_Baud.baud1200
		case .baud2400:
			return ModuleConfig.SerialConfig.Serial_Baud.baud2400
		case .baud4800:
			return ModuleConfig.SerialConfig.Serial_Baud.baud4800
		case .baud9600:
			return ModuleConfig.SerialConfig.Serial_Baud.baud9600
		case .baud19200:
			return ModuleConfig.SerialConfig.Serial_Baud.baud19200
		case .baud38400:
			return ModuleConfig.SerialConfig.Serial_Baud.baud38400
		case .baud57600:
			return ModuleConfig.SerialConfig.Serial_Baud.baud57600
		case .baud115200:
			return ModuleConfig.SerialConfig.Serial_Baud.baud115200
		case .baud230400:
			return ModuleConfig.SerialConfig.Serial_Baud.baud230400
		case .baud460800:
			return ModuleConfig.SerialConfig.Serial_Baud.baud460800
		case .baud576000:
			return ModuleConfig.SerialConfig.Serial_Baud.baud576000
		case .baud921600:
			return ModuleConfig.SerialConfig.Serial_Baud.baud921600
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
	func protoEnumValue() -> ModuleConfig.SerialConfig.Serial_Mode {
		
		switch self {
			
		case .modeDefault:
			return ModuleConfig.SerialConfig.Serial_Mode.default
		case .modeSimple:
			return ModuleConfig.SerialConfig.Serial_Mode.simple
		case .modeProto:
			return ModuleConfig.SerialConfig.Serial_Mode.proto
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
	
	var node: NodeInfoEntity?
	
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
			.disabled(!(node != nil && node!.myInfo?.hasWifi ?? false))
			
			Button {
							
				isPresentingSaveConfirm = true
				
			} label: {
				
				Label("Save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || !hasChanges || !(node!.myInfo?.hasWifi ?? false))
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				
				"Are you sure?",
				isPresented: $isPresentingSaveConfirm
			) {
				Button("Save Serial Module Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
						
					var sc = ModuleConfig.SerialConfig()
					sc.enabled = enabled
					sc.echo = echo
					sc.rxd = UInt32(rxd)
					sc.txd = UInt32(txd)
					sc.baud = SerialBaudRates(rawValue: baudRate)!.protoEnumValue()
					sc.timeout = UInt32(timeout)
					sc.mode	= SerialModeTypes(rawValue: mode)!.protoEnumValue()
					
					let adminMessageId =  bleManager.saveSerialModuleConfig(config: sc, fromUser: node!.user!, toUser: node!.user!)
					
					if adminMessageId > 0 {
						
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

					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
			})
			.onAppear {

				if self.initialLoad{
					
					self.bleManager.context = context
					
					self.enabled = node!.serialConfig?.enabled ?? false
					self.echo = node!.serialConfig?.echo ?? false
					self.rxd = Int(node!.serialConfig?.rxd ?? 0)
					self.txd = Int(node!.serialConfig?.txd ?? 0)
					self.baudRate = Int(node!.serialConfig?.baudRate ?? 0)
					self.timeout = Int(node!.serialConfig?.timeout ?? 0)
					self.mode = Int(node!.serialConfig?.mode ?? 0)
					
					self.hasChanges = false
					self.initialLoad = false
				}
			}
			.onChange(of: enabled) { newEnabled in
				
				if node != nil && node!.serialConfig != nil {
				
					if newEnabled != node!.serialConfig!.enabled { hasChanges = true	}
				}
			}
			.onChange(of: echo) { newEcho in
				
				if node != nil && node!.serialConfig != nil {
				
					if newEcho != node!.serialConfig!.echo { hasChanges = true	}
				}
			}
			.onChange(of: rxd) { newRxd in
				
				if node != nil && node!.serialConfig != nil {
				
					if newRxd != node!.serialConfig!.rxd { hasChanges = true	}
				}
			}
			.onChange(of: txd) { newTxd in
				
				if node != nil && node!.serialConfig != nil {

					if newTxd != node!.serialConfig!.txd { hasChanges = true	}
				}
			}
			.onChange(of: baudRate) { newBaud in
				
				if node != nil && node!.serialConfig != nil {
				
					if newBaud != node!.serialConfig!.baudRate { hasChanges = true	}
				}
			}
			.onChange(of: timeout) { newTimeout in
				
				if node != nil && node!.serialConfig != nil {
					
					if newTimeout != node!.serialConfig!.timeout { hasChanges = true	}
				}
			}
			.onChange(of: mode) { newMode in
				
				if node != nil && node!.serialConfig != nil {
					
					if newMode != node!.serialConfig!.mode { hasChanges = true	}
				}
			}
			.navigationViewStyle(StackNavigationViewStyle())
		}
	}
}
