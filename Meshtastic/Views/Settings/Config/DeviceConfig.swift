//
//  DeviceConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import SwiftUI

struct DeviceConfig: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@Environment(\.dismiss) private var goBack

	var node: NodeInfoEntity?

	@State private var isPresentingNodeDBResetConfirm = false
	@State private var isPresentingFactoryResetConfirm = false
	@State var hasChanges = false
	@State var deviceRole = 0
	@State var buzzerGPIO = 0
	@State var buttonGPIO = 0
	@State var serialEnabled = true
	@State var debugLogEnabled = false
	@State var rebroadcastMode = 0
	@State var nodeInfoBroadcastSecs = 10800
	@State var doubleTapAsButtonPress = false
	@State var isManaged = false
	@State var tzdef = ""

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Device", config: \.deviceConfig, node: node, onAppear: setDeviceValues)

				Section(header: Text("options")) {
					VStack(alignment: .leading) {
						Picker("Device Role", selection: $deviceRole ) {
							ForEach(DeviceRoles.allCases) { dr in
								Text(dr.name)
							}
						}
						Text(DeviceRoles(rawValue: deviceRole)?.description ?? "")
							.foregroundColor(.gray)
							.font(.callout)
					}
					.pickerStyle(DefaultPickerStyle())
					
					VStack(alignment: .leading) {
						Picker("Rebroadcast Mode", selection: $rebroadcastMode ) {
							ForEach(RebroadcastModes.allCases) { rm in
								Text(rm.name)
							}
						}
						Text(RebroadcastModes(rawValue: rebroadcastMode)?.description ?? "")
							.foregroundColor(.gray)
							.font(.callout)
					}
					.pickerStyle(DefaultPickerStyle())
					
					Picker("Node Info Broadcast Interval", selection: $nodeInfoBroadcastSecs ) {
						ForEach(UpdateIntervals.allCases) { ui in
							if ui.rawValue >= 3600 {
								Text(ui.description)
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Toggle(isOn: $doubleTapAsButtonPress) {
						Label("Double Tap as Button", systemImage: "hand.tap")
						Text("Treat double tap on supported accelerometers as a user button press.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $isManaged) {
						Label("Managed Device", systemImage: "gearshape.arrow.triangle.2.circlepath")
						Text("Enabling Managed mode will restrict access to all radio configurations, such as short/long names, regions, channels, modules, etc. and will only be accessible through the Admin channel. To avoid being locked out, make sure the Admin channel is working properly before enabling it.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
				Section(header: Text("Debug")) {
					Toggle(isOn: $serialEnabled) {
						Label("Serial Console", systemImage: "terminal")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Toggle(isOn: $debugLogEnabled) {
						Label("Debug Log", systemImage: "ant.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					VStack(alignment: .leading) {
						HStack {
							Label("Time Zone", systemImage: "clock.badge.exclamationmark")
							TextField("Time Zone", text: $tzdef, axis: .vertical)
								.foregroundColor(.gray)
								.onChange(of: tzdef, perform: { _ in
									let totalBytes = tzdef.utf8.count
									// Only mess with the value if it is too big
									if totalBytes > 63 {
										tzdef = String(tzdef.dropLast())
									}
								})
								.foregroundColor(.gray)
						
						}
						.keyboardType(.default)
						.disableAutocorrection(true)
						Text("Time zone for dates on the device screen and log.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}
				Section(header: Text("GPIO")) {
					Picker("Button GPIO", selection: $buttonGPIO) {
						ForEach(0..<49) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Picker("Buzzer GPIO", selection: $buzzerGPIO) {
						ForEach(0..<49) {
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
			.disabled(self.bleManager.connectedPeripheral == nil || node?.deviceConfig == nil)
			// Only show these buttons for the BLE connected node
			if bleManager.connectedPeripheral != nil && node?.num ?? -1  == bleManager.connectedPeripheral.num {
				HStack {
					Button("Reset NodeDB", role: .destructive) {
						isPresentingNodeDBResetConfirm = true
					}
					.disabled(node?.user == nil)
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.leading)
					.confirmationDialog(
						"are.you.sure",
						isPresented: $isPresentingNodeDBResetConfirm,
						titleVisibility: .visible
					) {
						Button("Erase all device and app data?", role: .destructive) {
							if bleManager.sendNodeDBReset(fromUser: node!.user!, toUser: node!.user!) {
								DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
									bleManager.disconnectPeripheral()
									clearCoreDataDatabase(context: context)
								}
								
							} else {
								print("NodeDB Reset Failed")
							}
						}
					}
					Button("Factory Reset", role: .destructive) {
						isPresentingFactoryResetConfirm = true
					}
					.disabled(node?.user == nil)
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.trailing)
					.confirmationDialog(
						"All device and app data will be deleted. You will also need to forget your devices under Settings > Bluetooth.",
						isPresented: $isPresentingFactoryResetConfirm,
						titleVisibility: .visible
					) {
						Button("Factory reset your device and app? ", role: .destructive) {
							if bleManager.sendFactoryReset(fromUser: node!.user!, toUser: node!.user!) {
								DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
									bleManager.disconnectPeripheral()
									clearCoreDataDatabase(context: context)
								}
							} else {
								print("Factory Reset Failed")
							}
						}
					}
				}
			}
			HStack {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if connectedNode != nil {
						var dc = Config.DeviceConfig()
						dc.role = DeviceRoles(rawValue: deviceRole)!.protoEnumValue()
						dc.serialEnabled = serialEnabled
						dc.debugLogEnabled = debugLogEnabled
						dc.buttonGpio = UInt32(buttonGPIO)
						dc.buzzerGpio = UInt32(buzzerGPIO)
						dc.rebroadcastMode = RebroadcastModes(rawValue: rebroadcastMode)?.protoEnumValue() ?? RebroadcastModes.all.protoEnumValue()
						dc.nodeInfoBroadcastSecs = UInt32(nodeInfoBroadcastSecs)
						dc.doubleTapAsButtonPress = doubleTapAsButtonPress
						dc.isManaged = isManaged
						dc.tzdef = tzdef
						if isManaged {
							serialEnabled = false
							debugLogEnabled = false
						}
						let adminMessageId = bleManager.saveDeviceConfig(config: dc, fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
						if adminMessageId > 0 {
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
							goBack()
						}
					}
				}
			}
			Spacer()
		}
		.navigationTitle("device.config")
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?")
		})
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			setDeviceValues()
			// Need to request a LoRaConfig from the remote node before allowing changes
			if bleManager.connectedPeripheral != nil && node?.deviceConfig == nil {
				print("empty device config")
				let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral?.num ?? -1, context: context)
				if node != nil && connectedNode != nil && connectedNode?.user != nil {
					_ = bleManager.requestDeviceConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: deviceRole) { newRole in
			if node != nil && node?.deviceConfig != nil {
				if newRole != node!.deviceConfig!.role { hasChanges = true }
			}
		}
		.onChange(of: serialEnabled) { newSerial in
			if node != nil && node?.deviceConfig != nil {
				if newSerial != node!.deviceConfig!.serialEnabled { hasChanges = true }
			}
		}
		.onChange(of: debugLogEnabled) { newDebugLog in
			if node != nil && node?.deviceConfig != nil {
				if newDebugLog != node!.deviceConfig!.debugLogEnabled {	hasChanges = true }
			}
		}
		.onChange(of: buttonGPIO) { newButtonGPIO in
			if node != nil && node?.deviceConfig != nil {
				if newButtonGPIO != node!.deviceConfig!.buttonGpio { hasChanges = true }
			}
		}
		.onChange(of: buzzerGPIO) { newBuzzerGPIO in
			if node != nil && node?.deviceConfig != nil {
				if newBuzzerGPIO != node!.deviceConfig!.buttonGpio { hasChanges = true }
			}
		}
		.onChange(of: rebroadcastMode) { newRebroadcastMode in
			if node != nil && node?.deviceConfig != nil {
				if newRebroadcastMode != node!.deviceConfig!.rebroadcastMode { hasChanges = true }
			}
		}
		.onChange(of: nodeInfoBroadcastSecs) { newNodeInfoBroadcastSecs in
			if node != nil && node?.deviceConfig != nil {
				if newNodeInfoBroadcastSecs != node!.deviceConfig!.nodeInfoBroadcastSecs { hasChanges = true }
			}
		}
		.onChange(of: doubleTapAsButtonPress) { newDoubleTapAsButtonPress in
			if node != nil && node?.deviceConfig != nil {
				if newDoubleTapAsButtonPress != node!.deviceConfig!.doubleTapAsButtonPress { hasChanges = true }
			}
		}
		.onChange(of: isManaged) { newIsManaged in
			if node != nil && node?.deviceConfig != nil {
				if newIsManaged != node!.deviceConfig!.isManaged { hasChanges = true }
			}
		}
		.onChange(of: tzdef) { newTzdef in
			if node != nil && node?.deviceConfig != nil {
				if newTzdef != node!.deviceConfig!.tzdef { hasChanges = true }
			}
		}
	}
	func setDeviceValues() {
		self.deviceRole = Int(node?.deviceConfig?.role ?? 0)
		self.serialEnabled = (node?.deviceConfig?.serialEnabled ?? true)
		self.debugLogEnabled = node?.deviceConfig?.debugLogEnabled ?? false
		self.buttonGPIO = Int(node?.deviceConfig?.buttonGpio ?? 0)
		self.buzzerGPIO = Int(node?.deviceConfig?.buzzerGpio ?? 0)
		self.rebroadcastMode = Int(node?.deviceConfig?.rebroadcastMode ?? 0)
		self.nodeInfoBroadcastSecs = Int(node?.deviceConfig?.nodeInfoBroadcastSecs ?? 900)
		if nodeInfoBroadcastSecs < 3600 {
			nodeInfoBroadcastSecs = 3600
		}
		self.doubleTapAsButtonPress = node?.deviceConfig?.doubleTapAsButtonPress ?? false
		self.isManaged = node?.deviceConfig?.isManaged ?? false
		if self.tzdef.isEmpty {
			self.tzdef = TimeZone.current.posixDescription
			self.hasChanges = true
		} else {
			self.hasChanges = false
		}
	}
}
