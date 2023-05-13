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
	@State private var isPresentingSaveConfirm = false
	@State var hasChanges = false
	
	@State var deviceRole = 0
	@State var buzzerGPIO = 0
	@State var buttonGPIO = 0
	@State var serialEnabled = true
	@State var debugLogEnabled = false
	@State var rebroadcastMode = 0
	@State var doubleTapAsButtonPress = false
	
	var body: some View {
		
		VStack {
			
			Form {
				if node != nil && node?.metadata == nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					Text("There has been no response to a request for device metadata over the admin channel for this node.")
						.font(.callout)
						.foregroundColor(.orange)
					
				} else if node != nil && node?.num ?? 0 != bleManager.connectedPeripheral?.num ?? 0 {
					// Let users know what is going on if they are using remote admin and don't have the config yet
					if node?.deviceConfig == nil {
						Text("Device config data was requested over the admin channel but no response has been returned from the remote node. You can check the status of admin message requests in the admin message log.")
							.font(.callout)
							.foregroundColor(.orange)
					} else {
						Text("Remote administration for: \(node?.user?.longName ?? "Unknown")")
							.font(.title3)
							.onAppear {
								setDeviceValues()
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
					
					Picker("Device Role", selection: $deviceRole ) {
						ForEach(DeviceRoles.allCases) { dr in
							Text(dr.name)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.padding(.top, 10)
					Text(DeviceRoles(rawValue: deviceRole)?.description ?? "")
						.foregroundColor(.gray)
						.font(.caption)
					
					Picker("Rebroadcast Mode", selection: $rebroadcastMode ) {
						ForEach(RebroadcastModes.allCases) { rm in
							Text(rm.name)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.padding(.top, 10)
					Text(RebroadcastModes(rawValue: rebroadcastMode)?.description ?? "")
						.foregroundColor(.gray)
						.font(.caption)
					
					Toggle(isOn: $doubleTapAsButtonPress) {
						Label("Double Tap as Button", systemImage: "hand.tap")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("Treat double tap on supported accelerometers as a user button press.")
						.font(.caption)
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
				}
				
				Section(header: Text("GPIO")) {
					
					Picker("Button GPIO", selection: $buttonGPIO) {
						ForEach(0..<46) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Picker("Buzzer GPIO", selection: $buzzerGPIO) {
						ForEach(0..<46) {
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
					.padding()
					.confirmationDialog(
						"are.you.sure",
						isPresented: $isPresentingNodeDBResetConfirm,
						titleVisibility: .visible
					) {
						Button("Erase all device and app data?", role: .destructive) {
							
							if bleManager.sendNodeDBReset(fromUser: node!.user!, toUser: node!.user!) {
								bleManager.disconnectPeripheral()
								clearCoreDataDatabase(context: context)
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
					.padding()
					.confirmationDialog(
						"All device and app data will be deleted. You will also need to forget your devices under Settings > Bluetooth.",
						isPresented: $isPresentingFactoryResetConfirm,
						titleVisibility: .visible
					) {
						Button("Factory reset your device and app? ", role: .destructive) {
							
							if bleManager.sendFactoryReset(fromUser: node!.user!, toUser: node!.user!) {
								bleManager.disconnectPeripheral()
								clearCoreDataDatabase(context: context)
							} else {
								print("Factory Reset Failed")
								
							}
						}
					}
				}
			}
			HStack {
				
				Button {
					isPresentingSaveConfirm = true
					
				} label: {
					Label("save", systemImage: "square.and.arrow.down")
				}
				.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.confirmationDialog(
					
					"are.you.sure",
					isPresented: $isPresentingSaveConfirm,
					titleVisibility: .visible
				) {
					let nodeName = node?.user?.longName ?? "unknown".localized
					let buttonText = String.localizedStringWithFormat("save.config %@".localized, nodeName)
					Button(buttonText) {
						let connectedNode = getNodeInfo(id: bleManager.connectedPeripheral.num, context: context)
						if connectedNode != nil {
							var dc = Config.DeviceConfig()
							dc.role = DeviceRoles(rawValue: deviceRole)!.protoEnumValue()
							dc.serialEnabled = serialEnabled
							dc.debugLogEnabled = debugLogEnabled
							dc.buttonGpio = UInt32(buttonGPIO)
							dc.buzzerGpio = UInt32(buzzerGPIO)
							dc.rebroadcastMode = RebroadcastModes(rawValue: rebroadcastMode)?.protoEnumValue() ?? RebroadcastModes.all.protoEnumValue()
							dc.doubleTapAsButtonPress = doubleTapAsButtonPress
							
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
			message: {
				Text("config.save.confirm")
			}
			}
			Spacer()
		}
		.navigationTitle("device.config")
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			self.bleManager.context = context
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
			
			if node != nil && node!.deviceConfig != nil {
				
				if newRole != node!.deviceConfig!.role { hasChanges = true }
			}
		}
		.onChange(of: serialEnabled) { newSerial in
			
			if node != nil && node!.deviceConfig != nil {
				
				if newSerial != node!.deviceConfig!.serialEnabled { hasChanges = true }
			}
		}
		.onChange(of: debugLogEnabled) { newDebugLog in
			
			if node != nil && node!.deviceConfig != nil {
				
				if newDebugLog != node!.deviceConfig!.debugLogEnabled {	hasChanges = true }
			}
		}
		.onChange(of: buttonGPIO) { newButtonGPIO in
			
			if node != nil && node!.deviceConfig != nil {
				
				if newButtonGPIO != node!.deviceConfig!.buttonGpio { hasChanges = true }
			}
		}
		.onChange(of: buzzerGPIO) { newBuzzerGPIO in
			
			if node != nil && node!.deviceConfig != nil {
				
				if newBuzzerGPIO != node!.deviceConfig!.buttonGpio { hasChanges = true }
			}
		}
		.onChange(of: rebroadcastMode) { newRebroadcastMode in
			
			if node != nil && node!.deviceConfig != nil {
				
				if newRebroadcastMode != node!.deviceConfig!.rebroadcastMode { hasChanges = true }
			}
		}
		.onChange(of: doubleTapAsButtonPress) { newDoubleTapAsButtonPress in
			
			if node != nil && node!.deviceConfig != nil {
				
				if newDoubleTapAsButtonPress != node!.deviceConfig!.doubleTapAsButtonPress { hasChanges = true }
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
		self.doubleTapAsButtonPress = node?.deviceConfig?.doubleTapAsButtonPress ?? false
		self.hasChanges = false
	}
}
