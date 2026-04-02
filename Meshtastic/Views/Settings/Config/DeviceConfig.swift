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
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingNodeDBResetConfirm = false
	@State private var isPresentingFactoryResetConfirm = false
	@State var hasChanges = false
	@State var deviceRole = 0
	@State var buzzerGPIO = 0
	@State var buttonGPIO = 0
	@State var rebroadcastMode = 0
	@State private var nodeInfoBroadcastSecs: UpdateInterval = UpdateInterval(from: 10800)
	@State var doubleTapAsButtonPress = false
	@State var ledHeartbeatEnabled = true
	@State var tripleClickAsAdHocPing = true
	@State var tzdef = ""
	@State private var showSpecialRoleWarning = false
	@State private var showSpecialRoleWarningForRole: Int = 0

	var body: some View {
		Form {
			ConfigHeader(title: "Device", config: \.deviceConfig, node: node, onAppear: setDeviceValues)
			
			Section(header: Text("Options")) {
				VStack(alignment: .leading) {
					Picker("Device Role", selection: $deviceRole ) {
						ForEach(DeviceRoles.allCases) { dr in
							Text(dr.name).tag(dr.rawValue as Int)
						}
					}
					.onChange(of: deviceRole) { _, newRole in
						if hasChanges && [DeviceRoles.router.rawValue, DeviceRoles.routerLate.rawValue, DeviceRoles.clientBase.rawValue].contains(newRole) {
							showSpecialRoleWarningForRole = newRole
							showSpecialRoleWarning = true
						}
					}
					.confirmationDialog(
						"Are you sure?",
						isPresented: $showSpecialRoleWarning,
						titleVisibility: .visible
					) {
						
						Button("Confirm") {
							hasChanges = true
						}
						Button("Cancel", role: .cancel) {
							setDeviceValues()
						}
					} message: {
						Text(specialRoleWarningMessage(newRole: showSpecialRoleWarningForRole))
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
				UpdateIntervalPicker(
					config: .broadcastLong,
					pickerLabel: "Node Info Broadcast Interval",
					selectedInterval: $nodeInfoBroadcastSecs
				)
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
							Text("Unset")
						} else {
							Text("Pin \($0)")
						}
					}
				}
				.pickerStyle(DefaultPickerStyle())
				Picker("Buzzer GPIO", selection: $buzzerGPIO) {
					ForEach(0..<49) {
						if $0 == 0 {
							Text("Unset")
						} else {
							Text("Pin \($0)")
						}
					}
				}
				.pickerStyle(DefaultPickerStyle())
			}
		}
		.disabled(!accessoryManager.isConnected || node?.deviceConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			VStack(spacing: 0) {
				// Only show these buttons for the BLE connected node
				if accessoryManager.isConnected, let device = accessoryManager.activeConnection?.device, node?.num ?? -1 == device.num {
					HStack {
						Button("Reset NodeDB", role: .destructive) {
							isPresentingNodeDBResetConfirm = true
						}
						.disabled(node?.user == nil)
						.buttonStyle(.borderedProminent)
						.buttonBorderShape(.capsule)
						.confirmationDialog(
							"Are you sure?",
							isPresented: $isPresentingNodeDBResetConfirm,
							titleVisibility: .visible
						) {
							Button("Erase all device and app data?", role: .destructive) {
								Task {
									do {
										try await accessoryManager.sendNodeDBReset(fromUser: node!.user!, toUser: node!.user!)
										try await Task.sleep(for: .seconds(1))
										try await accessoryManager.disconnect()
										await MeshPackets.shared.clearCoreDataDatabase(includeRoutes: false)
										clearNotifications()
									} catch {
										Logger.mesh.error("NodeDB Reset Failed")
									}
								}
							}
						}
						Button("Factory Reset", role: .destructive) {
							isPresentingFactoryResetConfirm = true
						}
						.disabled(node?.user == nil)
						.buttonStyle(.borderedProminent)
						.buttonBorderShape(.capsule)
						.confirmationDialog(
							"Factory reset will delete device and app data.",
							isPresented: $isPresentingFactoryResetConfirm,
							titleVisibility: .visible
						) {
							Button("Delete all config? ", role: .destructive) {
								Task {
									do {
										try await accessoryManager.sendFactoryReset(fromUser: node!.user!, toUser: node!.user!)
										try await Task.sleep(for: .seconds(1))
										try await accessoryManager.disconnect()
										await MeshPackets.shared.clearCoreDataDatabase(includeRoutes: false)
										clearNotifications()
									} catch {
										Logger.mesh.error("Factory Reset Failed")
									}
								}
							}
							Button("Delete all config, keys and BLE bonds? ", role: .destructive) {
								Task {
									do {
										try await accessoryManager.sendFactoryReset(fromUser: node!.user!, toUser: node!.user!, resetDevice: true)
										try? await Task.sleep(for: .seconds(1))
										try await accessoryManager.disconnect()
										await MeshPackets.shared.clearCoreDataDatabase(includeRoutes: false)
										clearNotifications()
									} catch {
										Logger.mesh.error("Factory Reset Failed")
									}
								}
							}
						}
					}
					.padding(.bottom)
				}
				HStack(spacing: 0) {
					SaveConfigButton(node: node, hasChanges: $hasChanges) {
						if let deviceNum = accessoryManager.activeDeviceNum,
						   let connectedNode = getNodeInfo(id: deviceNum, context: context) {
							var dc = Config.DeviceConfig()
							dc.role = DeviceRoles(rawValue: deviceRole)!.protoEnumValue()
							dc.buttonGpio = UInt32(buttonGPIO)
							dc.buzzerGpio = UInt32(buzzerGPIO)
							dc.rebroadcastMode = RebroadcastModes(rawValue: rebroadcastMode)?.protoEnumValue() ?? RebroadcastModes.all.protoEnumValue()
							dc.nodeInfoBroadcastSecs = UInt32(nodeInfoBroadcastSecs.intValue)
							dc.doubleTapAsButtonPress = doubleTapAsButtonPress
							dc.disableTripleClick = !tripleClickAsAdHocPing
							dc.tzdef = tzdef
							dc.ledHeartbeatDisabled = !ledHeartbeatEnabled
							Task {
								_ = try await accessoryManager.saveDeviceConfig(config: dc, fromUser: connectedNode.user!, toUser: node!.user!)
								Task { @MainActor in
									// Should show a saved successfully alert once I know that to be true
									// for now just disable the button after a successful save
									hasChanges = false
									goBack()
								}
							}
						}
					}
				}
			}
			.navigationTitle("Device Config")
			.navigationBarItems(
				trailing: ZStack {
					ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
					
				}
			)
		}
		.onFirstAppear {
			// Need to request a DeviceConfig from the remote node before allowing changes
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				let connectedNode = getNodeInfo(id: deviceNum, context: context)
				if let connectedNode {
					if node.num != deviceNum {
						if UserDefaults.enableAdministration {
							/// 2.5 Administration with session passkey
							let expiration = node.sessionExpiration ?? Date()
							if expiration < Date() || node.deviceConfig == nil {
								Task {
									do {
										Logger.mesh.info("⚙️ Empty or expired device config requesting via PKI admin")
										try await accessoryManager.requestDeviceConfig(fromUser: connectedNode.user!, toUser: node.user!)
									} catch {
										Logger.mesh.error("🚨 Device config request failed")
									}
								}
							}
						} else {
							if node.deviceConfig == nil {
								/// Legacy Administration
								Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
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
		.onChange(of: nodeInfoBroadcastSecs.intValue) { oldNodeInfoBroadcastSecs, newNodeInfoBroadcastSecs in
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
		if node?.deviceConfig?.role ?? 0 == 3 {
			node?.deviceConfig?.role = 1
		}
		self.deviceRole = Int(node?.deviceConfig?.role ?? 0)
		self.buttonGPIO = Int(node?.deviceConfig?.buttonGpio ?? 0)
		self.buzzerGPIO = Int(node?.deviceConfig?.buzzerGpio ?? 0)
		self.rebroadcastMode = Int(node?.deviceConfig?.rebroadcastMode ?? 0)
		self.nodeInfoBroadcastSecs = UpdateInterval(from: Int(node?.deviceConfig?.nodeInfoBroadcastSecs ?? 10800))
		if nodeInfoBroadcastSecs.intValue < 10800 {
			nodeInfoBroadcastSecs = UpdateInterval(from: 10800)
		}
		self.doubleTapAsButtonPress = node?.deviceConfig?.doubleTapAsButtonPress ?? false
		self.tripleClickAsAdHocPing = node?.deviceConfig?.tripleClickAsAdHocPing ?? false
		self.ledHeartbeatEnabled = node?.deviceConfig?.ledHeartbeatEnabled ?? true
		self.tzdef = node?.deviceConfig?.tzdef ?? ""
		hasChanges = false
	}

	private func specialRoleWarningMessage(newRole: Int) -> String {
		if [DeviceRoles.router.rawValue, DeviceRoles.routerLate.rawValue].contains(newRole) {
			return "The Router roles are only for high vantage locations like mountaintops and towers with few nearby nodes, not for use in urban areas. Improper use will hurt your local mesh."
		} else if newRole == DeviceRoles.clientBase.rawValue {
			return "Switching to Client Base will clear this node's favorites. Client Base should only favorite other nodes you control. Improper use will hurt your local mesh."
		} else {
			return ""
		}
	}
}
