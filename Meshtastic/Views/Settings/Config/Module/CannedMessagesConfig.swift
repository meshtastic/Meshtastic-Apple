//
//  CannedMessagesConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
import SwiftUI

struct CannedMessagesConfig: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack
	var node: NodeInfoEntity?
	@State private var isPresentingSaveConfirm: Bool = false
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
	@State var messages = ""
	var body: some View {
		VStack {
			Form {
				if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					Text("There has been no response to a request for device metadata over the admin channel for this node.")
						.font(.callout)
						.foregroundColor(.orange)

				} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					// Let users know what is going on if they are using remote admin and don't have the config yet
					if node?.cannedMessageConfig == nil {
						Text("Canned messages config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
							.font(.callout)
							.foregroundColor(.orange)
					} else {
						Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
							.font(.title3)
							.onAppear {
								setCannedMessagesValues()
							}
					}
				} else if node != nil && node?.num ?? 0 == bleManager.connectedPeripheral?.num ?? 0 {
					Text("Configuration for: \(node?.user?.longName ?? "Unknown")")
						.font(.title3)
				} else {
					Text("Please connect to a radio to configure settings.")
						.font(.callout)
						.foregroundColor(.orange)
				}
				Section(header: Text("options")) {
					Toggle(isOn: $enabled) {

						Label("enabled", systemImage: "list.bullet.rectangle.fill")
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
				HStack {
					Label("Messages", systemImage: "message.fill")
					TextField("Messages separate with |", text: $messages, axis: .vertical)
						.foregroundColor(.gray)
						.autocapitalization(.none)
						.disableAutocorrection(true)
						.onChange(of: messages, perform: { _ in

							let totalBytes = messages.utf8.count
							// Only mess with the value if it is too big
							if totalBytes > 198 {

								let firstNBytes = Data(messages.utf8.prefix(198))
								if let maxBytesString = String(data: firstNBytes, encoding: String.Encoding.utf8) {
									// Set the shortName back to the last place where it was the right size
									messages = maxBytesString
								}
							}
							hasMessagesChanges = true
						})
						.foregroundColor(.gray)
				}
				.keyboardType(.default)
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
						ForEach(0..<46) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("GPIO pin for rotary encoder A port.")
						.font(.caption)
					Picker("Pin B", selection: $inputbrokerPinB) {
						ForEach(0..<46) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("GPIO pin for rotary encoder B port.")
						.font(.caption)
					Picker("Press Pin", selection: $inputbrokerPinPress) {
						ForEach(0..<46) {
							if $0 == 0 {
								Text("unset")
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
					Picker("Clockwise Rotary Event", selection: $inputbrokerEventCw ) {
						ForEach(InputEventChars.allCases) { iec in
							Text(iec.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.padding(.top, 10)
					.padding(.bottom, 10)
					Picker("Counter Clockwise Rotary Event", selection: $inputbrokerEventCcw ) {
						ForEach(InputEventChars.allCases) { iec in
							Text(iec.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.padding(.top, 10)
					.padding(.bottom, 10)
					Picker("Encoder Press Event", selection: $inputbrokerEventPress ) {
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
			.scrollDismissesKeyboard(.immediately)
			.disabled(self.bleManager.connectedPeripheral == nil || node?.cannedMessageConfig == nil)
			Button {
				isPresentingSaveConfirm = true
			} label: {
				Label("save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || (!hasChanges && !hasMessagesChanges))
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			.confirmationDialog(
				"are.you.sure",
				isPresented: $isPresentingSaveConfirm,
				titleVisibility: .visible
			) {
				let nodeName = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "unknown".localized
				let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
				Button(buttonText) {
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
					if hasChanges {
						if connectedNode != nil {
							var cmc = ModuleConfig.CannedMessageConfig()
							cmc.enabled = enabled
							cmc.sendBell = sendBell
							cmc.rotary1Enabled = rotary1Enabled
							cmc.updown1Enabled = updown1Enabled
							if rotary1Enabled {
								/// Input event origin accepted by the canned messages
								/// Can be e.g. "rotEnc1", "upDownEnc1",  "cardkb",  or keyword "_any"
								cmc.allowInputSource = "rotEnc1"
							} else if updown1Enabled {
								cmc.allowInputSource = "upDown1"
							} else {
								cmc.allowInputSource = "_any"
							}
							cmc.inputbrokerPinA = UInt32(inputbrokerPinA)
							cmc.inputbrokerPinB = UInt32(inputbrokerPinB)
							cmc.inputbrokerPinPress = UInt32(inputbrokerPinPress)
							cmc.inputbrokerEventCw = InputEventChars(rawValue: inputbrokerEventCw)!.protoEnumValue()
							cmc.inputbrokerEventCcw = InputEventChars(rawValue: inputbrokerEventCcw)!.protoEnumValue()
							cmc.inputbrokerEventPress = InputEventChars(rawValue: inputbrokerEventPress)!.protoEnumValue()
							let adminMessageId =  bleManager.saveCannedMessageModuleConfig(config: cmc, fromUser: node!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
							if adminMessageId > 0 {
								// Should show a saved successfully alert once I know that to be true
								// for now just disable the button after a successful save
								hasChanges = false
								goBack()
							}
						}
					}
					if hasMessagesChanges {
						let adminMessageId =  bleManager.saveCannedMessageModuleMessages(messages: messages, fromUser: node!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
						if adminMessageId > 0 {
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasMessagesChanges = false
							if !hasChanges {
								bleManager.sendWantConfig()
								goBack()
							}
						}
					}
				}
			}
			message: {
				Text("config.save.confirm")
			}
			.navigationTitle("canned.messages.config")
			.navigationBarItems(trailing:
				ZStack {
					ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
			})
			.onAppear {
				self.bleManager.context = context
				setCannedMessagesValues()

				// Need to request a CannedMessagesModuleConfig from the remote node before allowing changes
				if bleManager.connectedPeripheral != nil && node?.cannedMessageConfig == nil {
					print("empty canned messages module config")
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if node != nil && connectedNode != nil {
						_ = bleManager.requestCannedMessagesModuleConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
					}
				}
			}
			.onChange(of: configPreset) { newPreset in

				if newPreset == 1 {

					// RAK Rotary Encoder
					updown1Enabled = true
					rotary1Enabled = false
					inputbrokerPinA = 4
					inputbrokerPinB = 10
					inputbrokerPinPress = 9
					inputbrokerEventCw = InputEventChars.down.rawValue
					inputbrokerEventCcw = InputEventChars.up.rawValue
					inputbrokerEventPress = InputEventChars.select.rawValue

				} else if newPreset == 2 {

					// CardKB / RAK Keypad
					updown1Enabled = false
					rotary1Enabled = false
					inputbrokerPinA = 0
					inputbrokerPinB = 0
					inputbrokerPinPress	= 0
					inputbrokerEventCw = InputEventChars.none.rawValue
					inputbrokerEventCcw = InputEventChars.none.rawValue
					inputbrokerEventPress = InputEventChars.none.rawValue
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
		}
	}
	func setCannedMessagesValues() {
		self.enabled = node?.cannedMessageConfig?.enabled ?? false
		self.sendBell = node?.cannedMessageConfig?.sendBell ?? false
		self.rotary1Enabled = node?.cannedMessageConfig?.rotary1Enabled ?? false
		self.updown1Enabled = node?.cannedMessageConfig?.updown1Enabled ?? false
		self.inputbrokerPinA = Int(node?.cannedMessageConfig?.inputbrokerPinA ?? 0)
		self.inputbrokerPinB = Int(node?.cannedMessageConfig?.inputbrokerPinB ?? 0)
		self.inputbrokerPinPress = Int(node?.cannedMessageConfig?.inputbrokerPinPress ?? 0)
		self.inputbrokerEventCw = Int(node?.cannedMessageConfig?.inputbrokerEventCw ?? 0)
		self.inputbrokerEventCcw = Int(node?.cannedMessageConfig?.inputbrokerEventCcw ?? 0)
		self.inputbrokerEventPress = Int(node?.cannedMessageConfig?.inputbrokerEventPress ?? 0)
		self.messages = node?.cannedMessageConfig?.messages ?? ""
		self.hasChanges = false
		self.hasMessagesChanges = false
	}
}
