//
//  DeviceConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//

import MeshtasticProtobufs
import OSLog
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
	@State var ledHeartbeatEnabled = true
	@State var isManaged = false
	@State var tzdef = ""
	
	var optionsSection: some View {
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

			Toggle(isOn: $isManaged) {
				Label("Managed Device", systemImage: "gearshape.arrow.triangle.2.circlepath")
				Text("Enabling Managed mode will restrict access to all radio configurations, such as short/long names, regions, channels, modules, etc. and will only be accessible through the Admin channel. To avoid being locked out, make sure the Admin channel is working properly before enabling it.")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			Picker("Node Info Broadcast Interval", selection: $nodeInfoBroadcastSecs ) {
				ForEach(UpdateIntervals.allCases) { ui in
					if ui.rawValue >= 3600 {
						Text(ui.description)
					}
				}
			}
			.pickerStyle(DefaultPickerStyle())
		}
	}
	
	var hardwareSection: some View {
		Section(header: Text("Hardware")) {

			Toggle(isOn: $doubleTapAsButtonPress) {
				Label("Double Tap as Button", systemImage: "hand.tap")
				Text("Treat double tap on supported accelerometers as a user button press.")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))

			Toggle(isOn: $ledHeartbeatEnabled) {
				Label("LED Heartbeat", systemImage: "waveform.path.ecg")
				Text("Controls the blinking LED on the device.  For most devices this will control one of the up to 4 LEDS, the charger and GPS LEDs are not controllable.")
			}
			.toggleStyle(SwitchToggleStyle(tint: .accentColor))
		}
	}
	
	var debugSection: some View {
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
	}
	
	var gpioSection: some View {
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
	
	var resetSection: some View {
		HStack {
			if let connectedPeripheral = bleManager.connectedPeripheral, let node, node.num == connectedPeripheral.num {
				Button("Reset NodeDB", role: .destructive) {
					isPresentingNodeDBResetConfirm = true
				}
				.disabled(node.user == nil)
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
						if bleManager.sendNodeDBReset(fromUser: node.user!, toUser: node.user!) {
							DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
								bleManager.disconnectPeripheral()
								clearCoreDataDatabase(context: context, includeRoutes: false)
							}

						} else {
							Logger.mesh.error("NodeDB Reset Failed")
						}
					}
				}
				
				Button("Factory Reset", role: .destructive) {
					isPresentingFactoryResetConfirm = true
				}
				.disabled(node.user == nil)
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
						if bleManager.sendFactoryReset(fromUser: node.user!, toUser: node.user!) {
							DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
								bleManager.disconnectPeripheral()
								clearCoreDataDatabase(context: context, includeRoutes: false)
							}
						} else {
							Logger.mesh.error("Factory Reset Failed")
						}
					}
				}
			}
		}
	}
	
	var saveConfigButton: some View {
		HStack {
		   SaveConfigButton(node: node, hasChanges: $hasChanges) {
			   if let connectedPeripheral = bleManager.connectedPeripheral,
				   let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context) {
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
				   dc.ledHeartbeatDisabled = !ledHeartbeatEnabled
				   if isManaged {
					   serialEnabled = false
					   debugLogEnabled = false
				   }
				   let adminMessageId = bleManager.saveDeviceConfig(
					   config: dc,
					   fromUser: connectedNode.user!,
					   toUser: node!.user!,
					   adminIndex: connectedNode.myInfo?.adminIndex ?? 0
				   )
				   if adminMessageId > 0 {
					   // Should show a saved successfully alert once I know that to be true
					   // for now just disable the button after a successful save
					   hasChanges = false
					   goBack()
				   }
			   }
		   }
	   }
	}

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Device", config: \.deviceConfig, node: node, onAppear: setDeviceValues)

				optionsSection
				hardwareSection
				debugSection
				gpioSection
			}
			.disabled(self.bleManager.connectedPeripheral == nil || node?.deviceConfig == nil)
			// Only show these buttons for the BLE connected node
			resetSection
			saveConfigButton
			Spacer()
		}
		.navigationTitle("device.config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: bleManager.connectedPeripheral?.shortName ?? "?"
				)
			}
		)
		.onAppear {
			if self.bleManager.context == nil {
				self.bleManager.context = context
			}
			setDeviceValues()
			// Need to request a LoRaConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, node?.deviceConfig == nil {
				Logger.mesh.info("empty device config")
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if node != nil && connectedNode != nil && connectedNode?.user != nil {
					_ = bleManager.requestDeviceConfig(fromUser: connectedNode!.user!, toUser: node!.user!, adminIndex: connectedNode?.myInfo?.adminIndex ?? 0)
				}
			}
		}
		.onChange(of: deviceRole) { _ in handleChanges() }
		.onChange(of: serialEnabled) { _ in handleChanges() }
		.onChange(of: debugLogEnabled) { _ in handleChanges() }
		.onChange(of: buttonGPIO) { _ in handleChanges() }
		.onChange(of: buzzerGPIO) { _ in handleChanges() }
		.onChange(of: rebroadcastMode) { _ in handleChanges() }
		.onChange(of: nodeInfoBroadcastSecs) { _ in handleChanges() }
		.onChange(of: doubleTapAsButtonPress) { _ in handleChanges() }
		.onChange(of: isManaged) { _ in handleChanges() }
		.onChange(of: tzdef) { _ in handleChanges() }
	}
	
	func handleChanges() {
		guard let deviceConfig = node?.deviceConfig else { return }
		if deviceConfig.role != deviceRole ||
			deviceConfig.serialEnabled != serialEnabled ||
			deviceConfig.debugLogEnabled != debugLogEnabled ||
			deviceConfig.buttonGpio != buttonGPIO ||
			deviceConfig.buzzerGpio != buzzerGPIO ||
			deviceConfig.rebroadcastMode != rebroadcastMode ||
			deviceConfig.nodeInfoBroadcastSecs != nodeInfoBroadcastSecs ||
			deviceConfig.doubleTapAsButtonPress != doubleTapAsButtonPress ||
			deviceConfig.isManaged != isManaged ||
			deviceConfig.tzdef != tzdef
		{
			hasChanges = true
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
		self.ledHeartbeatEnabled = node?.deviceConfig?.ledHeartbeatEnabled ?? true
		self.isManaged = node?.deviceConfig?.isManaged ?? false
		self.tzdef = node?.deviceConfig?.tzdef ?? ""
		if self.tzdef.isEmpty {
			self.tzdef = TimeZone.current.posixDescription
			self.hasChanges = true
		} else {
			self.hasChanges = false
		}
	}
}
