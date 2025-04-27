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
	@State private var pendingDeviceRole = 0
	@State var buzzerGPIO = 0
	@State var buttonGPIO = 0
	@State var rebroadcastMode = 0
	@State var nodeInfoBroadcastSecs = 10800
	@State var doubleTapAsButtonPress = false
	@State var ledHeartbeatEnabled = true
	@State var tripleClickAsAdHocPing = true
	@State var tzdef = ""
	
	@State private var showRouterWarning = false
	@State private var confirmWarning = false


	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Device", config: \.deviceConfig, node: node, onAppear: setDeviceValues)

				Section(header: Text("Options")) {
					VStack(alignment: .leading) {
						Picker("Device Role", selection: $deviceRole ) {
							ForEach(DeviceRoles.allCases) { dr in
								Text(dr.name).tag(dr.rawValue as Int)
							}
						}
						.onChange(of: deviceRole) { oldValue, newValue in
							if !confirmWarning {
								if [2, 11].contains(newValue) {
									pendingDeviceRole = newValue
									deviceRole = oldValue // Reset selection until confirmed
									showRouterWarning = true
								}
							} else {
								confirmWarning = false
							}
						}
						.confirmationDialog(
							"Are you sure?",
							isPresented: $showRouterWarning,
							titleVisibility: .visible
						) {

							Button("Confirm") {
								deviceRole = pendingDeviceRole
								pendingDeviceRole = 0
								confirmWarning = true
							}
							Button("Cancel", role: .cancel) {
								pendingDeviceRole = 0
							}
						} message: {
							Text("The Router roles are designed for high vantage locations like mountaintops and towers. This node needs to be able to have a good direct connection to most of the nodes on the network or else this will significantly hurt the network.")
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
				}
				Section(header: Text("Hardware")) {

					Toggle(isOn: $doubleTapAsButtonPress) {
						Label("Double Tap as Button", systemImage: "hand.tap")
						Text("Treat double tap on supported accelerometers as a user button press.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Toggle(isOn: $tripleClickAsAdHocPing) {
						Label("Triple Click Ad Hoc Ping", systemImage: "mappin")
						Text("Send a position on the primary channel when the user button is triple clicked.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))

					Toggle(isOn: $ledHeartbeatEnabled) {
						Label("LED Heartbeat", systemImage: "waveform.path.ecg")
						Text("Controls the blinking LED on the device.  For most devices this will control one of the up to 4 LEDS, the charger and GPS LEDs are not controllable.")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
				Section(header: Text("Debug")) {
					VStack(alignment: .leading) {
						HStack {
							Label("Time Zone", systemImage: "clock.badge.exclamationmark")
							TextField("Time Zone", text: $tzdef, axis: .vertical)
								.foregroundColor(.gray)
								.onChange(of: tzdef) {
									var totalBytes = tzdef.utf8.count
									// Only mess with the value if it is too big
									while totalBytes > 63 {
										tzdef = String(tzdef.dropLast())
										totalBytes = tzdef.utf8.count
									}
								}
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
					.controlSize(.regular)
					.padding(.leading)
					.confirmationDialog(
						"Are you sure?",
						isPresented: $isPresentingNodeDBResetConfirm,
						titleVisibility: .visible
					) {
						Button("Erase all device and app data?", role: .destructive) {
							if bleManager.sendNodeDBReset(fromUser: node!.user!, toUser: node!.user!) {
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
					.disabled(node?.user == nil)
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.regular)
					.padding(.trailing)
					.confirmationDialog(
						"All device and app data will be deleted.",
						isPresented: $isPresentingFactoryResetConfirm,
						titleVisibility: .visible
					) {
						Button("Factory reset your device and app? ", role: .destructive) {
							if bleManager.sendFactoryReset(fromUser: node!.user!, toUser: node!.user!) {
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
			HStack {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
					if connectedNode != nil {
						var dc = Config.DeviceConfig()
						dc.role = DeviceRoles(rawValue: deviceRole)!.protoEnumValue()
						dc.buttonGpio = UInt32(buttonGPIO)
						dc.buzzerGpio = UInt32(buzzerGPIO)
						dc.rebroadcastMode = RebroadcastModes(rawValue: rebroadcastMode)?.protoEnumValue() ?? RebroadcastModes.all.protoEnumValue()
						dc.nodeInfoBroadcastSecs = UInt32(nodeInfoBroadcastSecs)
						dc.doubleTapAsButtonPress = doubleTapAsButtonPress
						dc.disableTripleClick = !tripleClickAsAdHocPing
						dc.tzdef = tzdef
						dc.ledHeartbeatDisabled = !ledHeartbeatEnabled
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
			// Need to request a DeviceConfig from the remote node before allowing changes
			if let connectedPeripheral = bleManager.connectedPeripheral, let node {
				let connectedNode = getNodeInfo(id: connectedPeripheral.num, context: context)
				if let connectedNode {
					if node.num != connectedNode.num {
						if UserDefaults.enableAdministration {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.deviceConfig == nil {
								Logger.mesh.info("⚙️ Empty or expired device config requesting via PKI admin")
								_ = bleManager.requestDeviceConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						} else {
							if node.deviceConfig == nil {
								/// Legacy Administration
								Logger.mesh.info("☠️ Using insecure legacy admin, empty device config")
								_ = bleManager.requestDeviceConfig(fromUser: connectedNode.user!, toUser: node.user!, adminIndex: connectedNode.myInfo?.adminIndex ?? 0)
							}
						}
					}
				}
			}
		}
		.onChange(of: deviceRole) { oldRole, newRole in
			if oldRole != newRole && newRole != node?.deviceConfig?.role ?? -1 { hasChanges = true }
		}
		.onChange(of: buttonGPIO) { oldButtonGPIO, newButtonGPIO in
			if oldButtonGPIO != newButtonGPIO && newButtonGPIO != node?.deviceConfig?.buttonGpio ?? -1 { hasChanges = true }
		}
		.onChange(of: buzzerGPIO) { oldBuzzerGPIO, newBuzzerGPIO in
			if oldBuzzerGPIO != newBuzzerGPIO && newBuzzerGPIO != node?.deviceConfig?.buzzerGpio ?? -1 { hasChanges = true }
		}
		.onChange(of: rebroadcastMode) { oldRebroadcastMode, newRebroadcastMode in
			if oldRebroadcastMode != newRebroadcastMode && newRebroadcastMode != node?.deviceConfig?.rebroadcastMode ?? -1 { hasChanges = true }
		}
		.onChange(of: nodeInfoBroadcastSecs) { oldNodeInfoBroadcastSecs, newNodeInfoBroadcastSecs in
			if oldNodeInfoBroadcastSecs != newNodeInfoBroadcastSecs && newNodeInfoBroadcastSecs != node?.deviceConfig?.nodeInfoBroadcastSecs ?? -1 { hasChanges = true }
		}
		.onChange(of: doubleTapAsButtonPress) { oldDoubleTapAsButtonPress, newDoubleTapAsButtonPress in
			if oldDoubleTapAsButtonPress != newDoubleTapAsButtonPress && newDoubleTapAsButtonPress != node?.deviceConfig?.doubleTapAsButtonPress ?? false { hasChanges = true }
		}
		.onChange(of: tripleClickAsAdHocPing) { oldTripleClickAsAdHocPing, newTripleClickAsAdHocPing in
			if oldTripleClickAsAdHocPing != newTripleClickAsAdHocPing && newTripleClickAsAdHocPing != node?.deviceConfig?.tripleClickAsAdHocPing ?? false { hasChanges = true }
		}
		.onChange(of: tzdef) { oldTzdef, newTzdef in
			if oldTzdef != newTzdef && newTzdef != node?.deviceConfig?.tzdef { hasChanges = true }
		}
		.onChange(of: ledHeartbeatEnabled) { oldLedHeartbeatEnabled, newLedHeartbeatEnabled in
			if oldLedHeartbeatEnabled != newLedHeartbeatEnabled && newLedHeartbeatEnabled != node?.deviceConfig?.ledHeartbeatEnabled ?? false { hasChanges = true }
		}
	}
	func setDeviceValues() {
		self.deviceRole = Int(node?.deviceConfig?.role ?? 0)
		self.buttonGPIO = Int(node?.deviceConfig?.buttonGpio ?? 0)
		self.buzzerGPIO = Int(node?.deviceConfig?.buzzerGpio ?? 0)
		self.rebroadcastMode = Int(node?.deviceConfig?.rebroadcastMode ?? 0)
		self.nodeInfoBroadcastSecs = Int(node?.deviceConfig?.nodeInfoBroadcastSecs ?? 900)
		if nodeInfoBroadcastSecs < 3600 {
			nodeInfoBroadcastSecs = 3600
		}
		self.doubleTapAsButtonPress = node?.deviceConfig?.doubleTapAsButtonPress ?? false
		self.tripleClickAsAdHocPing = node?.deviceConfig?.tripleClickAsAdHocPing ?? false
		self.ledHeartbeatEnabled = node?.deviceConfig?.ledHeartbeatEnabled ?? true
		self.tzdef = node?.deviceConfig?.tzdef ?? ""
		if self.tzdef.isEmpty {
			self.tzdef = TimeZone.current.posixDescription
			self.hasChanges = true
		} else {
			self.hasChanges = false
		}
	}
}
