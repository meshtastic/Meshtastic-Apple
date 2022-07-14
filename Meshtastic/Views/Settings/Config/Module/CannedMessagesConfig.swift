//
//  CannedMessagesConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
import SwiftUI

// Default of 0 is unset
enum ConfigPresets : Int, CaseIterable, Identifiable {

	case unset = 0
	case rakRotaryEncoder = 1
	case tbeamThreeButtonScreen = 2
	case cardKB = 3
	case facesKB = 4
	
	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			
			case .unset:
				return "Manual Configuration"
			case .rakRotaryEncoder:
				return "RAK Rotary Encoder Module"
			case .tbeamThreeButtonScreen:
				return "TBEAM 3 Button OLED Screen"
			case .cardKB:
				return "M5 Stack Card KeyBoard"
			case .facesKB:
				return "M5 Stack Faces KeyBoard"
			}
		}
	}
}

// Default of 0 is off
enum InputEventChars: Int, CaseIterable, Identifiable {

	case keyNone = 0
	case keyUp = 17
	case keyDown = 18
	case keyLeft = 19
	case keyRight = 20
	case keySelect = 10
	case keyBack = 27
	case keyCancel = 24

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			
			case .keyNone:
				return "None"
			case .keyUp:
				return "Up"
			case .keyDown:
				return "Down"
			case .keyLeft:
				return "Left"
			case .keyRight:
				return "Right"
			case .keySelect:
				return "Select"
			case .keyBack:
				return "Back"
			case .keyCancel:
				return "Cancel"
			}
		}
	}
	func protoEnumValue() -> ModuleConfig.CannedMessageConfig.InputEventChar {
		
		switch self {

		case .keyNone:
			return ModuleConfig.CannedMessageConfig.InputEventChar.keyNone
		case .keyUp:
			return ModuleConfig.CannedMessageConfig.InputEventChar.keyUp
		case .keyDown:
			return ModuleConfig.CannedMessageConfig.InputEventChar.keyDown
		case .keyLeft:
			return ModuleConfig.CannedMessageConfig.InputEventChar.keyLeft
		case .keyRight:
			return ModuleConfig.CannedMessageConfig.InputEventChar.keyRight
		case .keySelect:
			return ModuleConfig.CannedMessageConfig.InputEventChar.keySelect
		case .keyBack:
			return ModuleConfig.CannedMessageConfig.InputEventChar.keyBack
		case .keyCancel:
			return ModuleConfig.CannedMessageConfig.InputEventChar.keyCancel
		}
	}
}

struct CannedMessagesConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges = false
	@State var hasMessagesChanges = false
	@State var configPreset = 0
	
	@State var enabled = false
	/// CannedMessageModule will sends a bell character with the messages.
	@State var sendBell: Bool = false
	/// Enable the rotary encoder #1. This is a 'dumb' encoder sending pulses on both A and B pins while rotating.
	@State var rotary1Enabled = false
	/// Enable the Up/Down/Select input device. Can be RAK rotary encoder or 3 buttons. Uses the a/b/press definitions from inputbroker.
	@State var updown1Enabled: Bool = false
	/// GPIO pin for rotary encoder A port.
	@State var inputbrokerPinA = 0
	/// GPIO pin for rotary encoder B port.
	@State var inputbrokerPinB = 0
	/// GPIO pin for rotary encoder Press port.
	@State var inputbrokerPinPress = 0
	/// Generate input event on CW of this kind.
	@State var inputbrokerEventCw = 0
	/// Generate input event on CCW of this kind.
	@State var inputbrokerEventCcw = 0
	/// Generate input event on Press of this kind.
	@State var inputbrokerEventPress = 0
	
	@State var messagesPart1 = ""
	
	var body: some View {
		
		VStack {

			Form {
				
				Section(header: Text("Options")) {
				
					Toggle(isOn: $enabled) {

						Label("Enabled", systemImage: "list.bullet.rectangle.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $sendBell) {

						Label("Send Bell", systemImage: "bell")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Picker("Configuration Presets", selection: $configPreset ) {
						ForEach(ConfigPresets.allCases) { cp in
							Text(cp.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.padding(.top, 10)
					.padding(.bottom, 10)
					
				}
				Section(header: Text("Messages")) {
					
					TextEditor(text: $messagesPart1)
				}
				Section(header: Text("Control Type")) {
					
					
					Toggle(isOn: $rotary1Enabled) {

						Label("Rotary 1", systemImage: "dial.min")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.disabled(updown1Enabled)
					
					Toggle(isOn: $updown1Enabled) {

						Label("Up Down 1", systemImage: "arrow.up.arrow.down")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.disabled(rotary1Enabled)
					
				}
				.disabled(configPreset > 0)
				Section(header: Text("Inputs")) {
				
					Picker("Pin A", selection: $inputbrokerPinA) {
						ForEach(0..<40) {
							
							if $0 == 0 {
								
								Text("Unset")
								
							} else {
							
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("GPIO pin for rotary encoder A port.")
						.font(.caption)
					
					Picker("Pin B", selection: $inputbrokerPinB) {
						ForEach(0..<40) {
							
							if $0 == 0 {
								
								Text("Unset")
								
							} else {
							
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("GPIO pin for rotary encoder B port.")
						.font(.caption)
					
					Picker("Press Pin", selection: $inputbrokerPinPress) {
						ForEach(0..<40) {
							
							if $0 == 0 {
								
								Text("Unset")
								
							} else {
							
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("GPIO pin for rotary encoder Press port.")
						.font(.caption)
					
				}
				.disabled(configPreset > 0)
				
				Section(header: Text("Key Mapping")) {
					
					Picker("inputbrokerEventCw", selection: $inputbrokerEventCw ) {
						ForEach(InputEventChars.allCases) { iec in
							Text(iec.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.padding(.top, 10)
					.padding(.bottom, 10)
					
					Picker("inputbrokerEventCcw", selection: $inputbrokerEventCcw ) {
						ForEach(InputEventChars.allCases) { iec in
							Text(iec.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.padding(.top, 10)
					.padding(.bottom, 10)
					
					Picker("inputBrokerEventPress", selection: $inputbrokerEventPress ) {
						ForEach(InputEventChars.allCases) { iec in
							Text(iec.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.padding(.top, 10)
					.padding(.bottom, 10)
				}
				.disabled(configPreset > 0)
			}
			.disabled(bleManager.connectedPeripheral == nil)
			
			Button {
							
				isPresentingSaveConfirm = true
				
			} label: {
				
				Label("Save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || (!hasChanges && !hasMessagesChanges))
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				
				"Are you sure?",
				isPresented: $isPresentingSaveConfirm
			) {
				Button("Save Canned Messages Module Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
						
					if hasChanges {
					
						var cmc = ModuleConfig.CannedMessageConfig()
						cmc.enabled = enabled
						cmc.sendBell = sendBell
						cmc.rotary1Enabled = rotary1Enabled
						cmc.updown1Enabled = updown1Enabled
						if rotary1Enabled {
							
							/// Input event origin accepted by the canned messages
							/// Can be e.g. "rotEnc1", "upDownEnc1",  "cardkb", "faceskb" 623or keyword "_any"
							cmc.allowInputSource = "rotEnc1"
							
						} else if updown1Enabled {
							
							cmc.allowInputSource = "upDownEnc1"
							
						} else {
							
							cmc.allowInputSource = "_any"
						}
						cmc.inputbrokerPinA = UInt32(inputbrokerPinA)
						cmc.inputbrokerPinB = UInt32(inputbrokerPinB)
						cmc.inputbrokerPinPress = UInt32(inputbrokerPinPress)
						cmc.inputbrokerEventCw = InputEventChars(rawValue: inputbrokerEventCw)!.protoEnumValue()
						cmc.inputbrokerEventCcw = InputEventChars(rawValue: inputbrokerEventCcw)!.protoEnumValue()
						cmc.inputbrokerEventPress = InputEventChars(rawValue: inputbrokerEventPress)!.protoEnumValue()
						
						let adminMessageId =  bleManager.saveCannedMessageModuleConfig(config: cmc, fromUser: node!.user!, toUser: node!.user!, wantResponse: true)
							
						if adminMessageId > 0 {
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
						}
					}
					
					if hasMessagesChanges {
						
						let adminMessageId =  bleManager.saveCannedMessageModuleMessages(messages: messagesPart1, fromUser: node!.user!, toUser: node!.user!, wantResponse: true)
							
						if adminMessageId > 0 {
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasMessagesChanges = false
						}
						
					}
				}
			}
			
			.navigationTitle("Canned Messages Config")
			.navigationBarItems(trailing:

				ZStack {

					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
			})
			.onAppear {

				if self.initialLoad{
					
					self.bleManager.context = context
					self.enabled = node!.cannedMessageConfig?.enabled ?? false
					self.sendBell = node!.cannedMessageConfig?.sendBell ?? false
					self.rotary1Enabled = node!.cannedMessageConfig?.rotary1Enabled ?? false
					self.updown1Enabled = node!.cannedMessageConfig?.updown1Enabled ?? false
					self.inputbrokerPinA = Int(node!.cannedMessageConfig?.inputbrokerPinA ?? 0)
					self.inputbrokerPinB = Int(node!.cannedMessageConfig?.inputbrokerPinB ?? 0)
					self.inputbrokerPinPress = Int(node!.cannedMessageConfig?.inputbrokerPinPress ?? 0)
					self.hasChanges = false
					self.initialLoad = false
				}
			}
			.onChange(of: configPreset) { newPreset in
				
				if newPreset == 1 {
					
					// RAK Rotary Encoder
					updown1Enabled = true
					rotary1Enabled = false
					
				} else if newPreset == 2 {
					
					// TBeam Three Button 1.3" OLED Screen
					updown1Enabled = true
					rotary1Enabled = false
					inputbrokerPinA = 25
					inputbrokerPinB = 39
					inputbrokerPinPress	= 36
					inputbrokerEventCw = InputEventChars.keyUp.rawValue
					inputbrokerEventCcw = InputEventChars.keyDown.rawValue
					inputbrokerEventPress = InputEventChars.keySelect.rawValue
				}
				
				hasChanges = true
			}
			.onChange(of: enabled) { newEnabled in
				
				if node != nil && node!.cannedMessageConfig != nil {
				
					if newEnabled != node!.cannedMessageConfig!.enabled { hasChanges = true }
				}
			}
			.onChange(of: sendBell) { newBell in
				
				if node != nil && node!.cannedMessageConfig != nil {
					
					if newBell != node!.cannedMessageConfig!.sendBell { hasChanges = true }
				}
			}
			.onChange(of: rotary1Enabled) { newRot1 in
				
				if node != nil && node!.cannedMessageConfig != nil {
				
					if newRot1 != node!.cannedMessageConfig!.rotary1Enabled { hasChanges = true	}
				}
			}
			.onChange(of: updown1Enabled) { newUpDown in
				
				if node != nil && node!.cannedMessageConfig != nil {
					
					if newUpDown != node!.cannedMessageConfig!.updown1Enabled { hasChanges = true }
				}
			}
			.onChange(of: inputbrokerPinA) { newPinA in
				
				if node != nil && node!.cannedMessageConfig != nil {
					
					if newPinA != node!.cannedMessageConfig!.inputbrokerPinA { hasChanges = true }
				}
			}
			.onChange(of: inputbrokerPinB) { newPinB in
				if node != nil && node!.cannedMessageConfig != nil {
				
					if newPinB != node!.cannedMessageConfig!.inputbrokerPinB { hasChanges = true }
				}
			}
			.onChange(of: inputbrokerPinPress) { newPinPress in
				if node != nil && node!.cannedMessageConfig != nil {
				
					if newPinPress != node!.cannedMessageConfig!.inputbrokerPinPress { hasChanges = true }
				}
			}
			.onChange(of: inputbrokerEventCw) { newKeyA in
				if node != nil && node!.cannedMessageConfig != nil {
				
					if newKeyA != node!.cannedMessageConfig!.inputbrokerEventCw { hasChanges = true	}
				}
			}
			.onChange(of: inputbrokerEventCcw) { newKeyB in
				
				if node != nil && node!.cannedMessageConfig != nil {
				
					if newKeyB != node!.cannedMessageConfig!.inputbrokerEventCcw { hasChanges = true }
				}
			}
			.onChange(of: inputbrokerEventPress) { newKeyPress in
				
				if node != nil && node!.cannedMessageConfig != nil {
					
					if newKeyPress != node!.cannedMessageConfig!.inputbrokerEventPress { hasChanges = true }
				}
			}
			.onChange(of: messagesPart1) { newMessagesChanges in
				
				if node != nil && node!.cannedMessageConfig != nil {
					
					hasMessagesChanges = true
				}
			}
			.navigationViewStyle(StackNavigationViewStyle())
		}
	}
}
