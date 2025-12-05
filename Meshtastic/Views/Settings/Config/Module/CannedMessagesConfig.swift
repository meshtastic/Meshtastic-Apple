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
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var hasChanges = false
	@State var hasMessagesChanges = false
	@State var configPreset = 0
	@State var enabled = false
	@State var sendBell: Bool = false
	@State var rotary1Enabled = false
	@State var updown1Enabled: Bool = false
	@State var inputbrokerPinA = 0
	@State var inputbrokerPinB = 0
	@State var inputbrokerPinPress = 0
	@State var inputbrokerEventCw = 0
	@State var inputbrokerEventCcw = 0
	@State var inputbrokerEventPress = 0
	
	// This is the source of truth for the backend (pipe-separated)
	@State private var messages = ""
	
	// Derived array for nice List UI
	@State private var messageList: [String] = []
	@FocusState private var focusedIndex: Int?
	
	var body: some View {
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
				
				Picker("Configuration Presets", selection: $configPreset) {
					ForEach(ConfigPresets.allCases) { cp in
						Text(cp.description)
					}
				}
				.pickerStyle(.menu)
			}
			
			Section(header: Text("Messages")) {
				if messageList.isEmpty {
					Text("No messages yet. Tap + to add one.")
						.foregroundColor(.secondary)
						.italic()
				}
				
				List {
					ForEach(messageList.indices, id: \.self) { index in
						TextField("Message", text: $messageList[index], axis: .vertical)
							.lineLimit(2...8)
							.focused($focusedIndex, equals: index)
							.onChange(of: messageList[index]) {
								syncListToString()
							}

					}
					.onDelete(perform: deleteMessages)
					.onMove(perform: moveMessages)
				}
				
				Button {
					messageList.append("")
				} label: {
					Label("Add Message", systemImage: "plus.circle.fill")
						.foregroundColor(.accentColor)
				}
			}
			
			// Rest of your sections unchanged...
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
								Text("unset")
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
								Text("unset")
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
								Text("unset")
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
		.disabled(!accessoryManager.isConnected || node?.cannedMessageConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					// Your existing save logic — unchanged!
					let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? -1, context: context)
					if hasChanges {
						var cmc = ModuleConfig.CannedMessageConfig()
						cmc.enabled = enabled
						cmc.sendBell = sendBell
						cmc.rotary1Enabled = rotary1Enabled
						cmc.updown1Enabled = updown1Enabled
						cmc.allowInputSource = rotary1Enabled ? "rotEnc1" : (updown1Enabled ? "upDown1" : "_any")
						cmc.inputbrokerPinA = UInt32(inputbrokerPinA)
						cmc.inputbrokerPinB = UInt32(inputbrokerPinB)
						cmc.inputbrokerPinPress = UInt32(inputbrokerPinPress)
						cmc.inputbrokerEventCw = InputEventChars(rawValue: inputbrokerEventCw)!.protoEnumValue()
						cmc.inputbrokerEventCcw = InputEventChars(rawValue: inputbrokerEventCcw)!.protoEnumValue()
						cmc.inputbrokerEventPress = InputEventChars(rawValue: inputbrokerEventPress)!.protoEnumValue()
						
						Task {
							do {
								_ = try await accessoryManager.saveCannedMessageModuleConfig(config: cmc, fromUser: node!.user!, toUser: node!.user!)
								await MainActor.run { hasChanges = false }
							} catch {
								Logger.mesh.error("Save config failed")
							}
						}
					}
					
					if hasMessagesChanges {
						Task {
							do {
								_ = try await accessoryManager.saveCannedMessageModuleMessages(messages: messages, fromUser: node!.user!, toUser: node!.user!)
								await MainActor.run {
									hasMessagesChanges = false
									if !hasChanges { goBack() }
								}
							} catch {
								Logger.mesh.error("Save messages failed")
							}
						}
					}
				}
			}
		}
		.navigationTitle("Canned Messages Config")
		.navigationBarItems(trailing: ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?"))
		.onAppear {
			setCannedMessagesValues()
		}
	}
	
	// MARK: - Helper: Sync List to Pipe String
	private func syncListToString() {
		let cleaned = messageList
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
		
		let newString = cleaned.joined(separator: "|")
		
		if newString != messages {
			messages = newString
			hasMessagesChanges = true
			hasChanges = true
		}
	}
	
	private func deleteMessages(at offsets: IndexSet) {
		messageList.remove(atOffsets: offsets)
		syncListToString()
	}
	
	private func moveMessages(from source: IndexSet, to destination: Int) {
		messageList.move(fromOffsets: source, toOffset: destination)
		syncListToString()
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
		
		// Populate the list from pipe string
		if messages.isEmpty {
			messageList = [""]
		} else {
			messageList = messages.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
		}
		
		self.hasChanges = false
		self.hasMessagesChanges = false
	}
}

