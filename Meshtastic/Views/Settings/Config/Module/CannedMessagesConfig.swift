//
//  CannedMessagesConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
import MeshtasticProtobufs
import OSLog
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
				ConfigHeader(title: "Canned messages", config: \.cannedMessageConfig, node: node, onAppear: setCannedMessagesValues)

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
				HStack {
					Label("Messages", systemImage: "message.fill")
					TextField("Messages separate with |", text: $messages, axis: .vertical)
						.foregroundColor(.gray)
						.autocapitalization(.none)
						.disableAutocorrection(true)
						.onChange(of: messages) {
							var totalBytes = messages.utf8.count
							// Only mess with the value if it is too big
							while totalBytes > 198 {
								messages = String(messages.dropLast())
								totalBytes = messages.utf8.count
							}
							if messages != node?.cannedMessageConfig?.messages ?? "" {
								hasChanges = true
								hasMessagesChanges = true
							}
						}
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
					VStack(alignment: .leading) {
						Picker("Pin A", selection: $inputbrokerPinA) {
							ForEach(0..<49) {
								if $0 == 0 {
									Text("Unset")
								} else {
									Text("Pin \($0)")
								}
							}
						}
						.pickerStyle(DefaultPickerStyle())
						Text("GPIO pin for rotary encoder A port.")
							.foregroundColor(.gray)
							.font(.callout)
					}
					VStack(alignment: .leading) {
						Picker("Pin B", selection: $inputbrokerPinB) {
							ForEach(0..<49) {
								if $0 == 0 {
									Text("Unset")
								} else {
									Text("Pin \($0)")
								}
							}
						}
						.pickerStyle(DefaultPickerStyle())
						Text("GPIO pin for rotary encoder B port.")
							.foregroundColor(.gray)
							.font(.callout)
					}
					VStack(alignment: .leading) {
						Picker("Press Pin", selection: $inputbrokerPinPress) {
							ForEach(0..<49) {
								if $0 == 0 {
									Text("Unset")
								} else {
									Text("Pin \($0)")
								}
							}
						}
						.pickerStyle(DefaultPickerStyle())
						Text("GPIO pin for rotary encoder Press port.")
							.foregroundColor(.gray)
							.font(.callout)
					}
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

			SaveConfigButton(node: node, hasChanges: $hasChanges) {
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
						let messagesAdminMessageId =  bleManager.saveCannedMessageModuleMessages(messages: messages, fromUser: node!.user!, toUser: node!.user!)
						if messagesAdminMessageId > 0 {
							// Fire off the message update ever time
							hasMessagesChanges = false
						}
						let adminMessageId =  bleManager.saveCannedMessageModuleConfig(config: cmc, fromUser: node!.user!, toUser: node!.user!)
						if adminMessageId > 0 {
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
							goBack()
						}
					}
				}
			}
			.navigationTitle("Canned Messages Config")
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
				// Need to request a CannedMessagesModuleConfig from the remote node before allowing changes
				if let connectedPeripheral = bleManager.connectedPeripheral, let node {
					let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
					if let connectedNode {
						if node.num != connectedNode.num {
							if UserDefaults.enableAdministration && node.num != connectedNode.num {
								/// 2.5 Administration with session passkey
								let expiration = node.sessionExpiration ?? Date()
								if expiration < Date() || node.cannedMessageConfig == nil {
									Logger.mesh.info("⚙️ Empty or expired canned messages module config requesting via PKI admin")
									_ = bleManager.requestCannedMessagesModuleConfig(fromUser: connectedNode.user!, toUser: node.user!)
								}
							} else {
								/// Legacy Administration
								Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
							}
						}
					}
				}
			}
			.onChange(of: configPreset) { _, newPreset in

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
			.onChange(of: enabled) { _, newEnabled in
				if newEnabled != node?.cannedMessageConfig?.enabled { hasChanges = true }
			}
			.onChange(of: sendBell) { _, newSendBell in
				if newSendBell != node?.cannedMessageConfig?.sendBell { hasChanges = true }
			}
			.onChange(of: rotary1Enabled) { _, newRotary1Enabled in
				if newRotary1Enabled != node?.cannedMessageConfig?.rotary1Enabled {	hasChanges = true }
			}
			.onChange(of: updown1Enabled) { _, newUpdown1Enabled in
				if newUpdown1Enabled != node?.cannedMessageConfig?.updown1Enabled {	hasChanges = true }
			}
			.onChange(of: inputbrokerPinA) { _, newPinA in
				if newPinA != node?.cannedMessageConfig?.inputbrokerPinA ?? -1 { hasChanges = true }
			}
			.onChange(of: inputbrokerPinB) { _, newPinB in
				if newPinB != node?.cannedMessageConfig?.inputbrokerPinB ?? -1 { hasChanges = true }
			}
			.onChange(of: inputbrokerPinPress) { _, newPinPress in
				if newPinPress != node?.cannedMessageConfig?.inputbrokerPinPress ?? -1 { hasChanges = true }
			}
			.onChange(of: inputbrokerEventCw) { _, newKeyA in
				if newKeyA != node?.cannedMessageConfig?.inputbrokerEventCw ?? -1 { hasChanges = true }
			}
			.onChange(of: inputbrokerEventCcw) { _, newKeyB in
				if newKeyB != node?.cannedMessageConfig?.inputbrokerEventCcw ?? -1 { hasChanges = true }
			}
			.onChange(of: inputbrokerEventPress) { _, newKeyPress in
				if newKeyPress != node?.cannedMessageConfig?.inputbrokerEventPress ?? -1 { hasChanges = true }
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
