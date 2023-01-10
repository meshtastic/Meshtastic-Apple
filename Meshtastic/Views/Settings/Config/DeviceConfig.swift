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
	
	var body: some View {
			
		VStack {

			Form {
				
				Section(header: Text("options")) {
					
					Picker("Device Role", selection: $deviceRole ) {
						ForEach(DeviceRoles.allCases) { dr in
							Text(dr.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					.padding(.top, 10)
					.padding(.bottom, 10)
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
						ForEach(0..<40) {
							if $0 == 0 {
								Text("unset")
							} else {
								Text("Pin \($0)")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Picker("Buzzer GPIO", selection: $buzzerGPIO) {
						ForEach(0..<40) {
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
			.disabled(bleManager.connectedPeripheral == nil)
			
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
					let nodeName = bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : NSLocalizedString("unknown", comment: "Unknown")
					let buttonText = String.localizedStringWithFormat(NSLocalizedString("save.config %@", comment: "Save Config for %@"), nodeName)
					Button(buttonText) {
						
						var dc = Config.DeviceConfig()
						dc.role = DeviceRoles(rawValue: deviceRole)!.protoEnumValue()
						dc.serialEnabled = serialEnabled
						dc.debugLogEnabled = debugLogEnabled
						dc.buttonGpio = UInt32(buttonGPIO)
						dc.buzzerGpio = UInt32(buzzerGPIO)
						
						let adminMessageId = bleManager.saveDeviceConfig(config: dc, fromUser: node!.user!, toUser: node!.user!)
						if adminMessageId > 0 {
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
							goBack()
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
			self.deviceRole = Int(node?.deviceConfig?.role ?? 0)
			self.serialEnabled = (node?.deviceConfig?.serialEnabled ?? true)
			self.debugLogEnabled = node?.deviceConfig?.debugLogEnabled ?? false
			self.buttonGPIO = Int(node?.deviceConfig?.buttonGpio ?? 0)
			self.buzzerGPIO = Int(node?.deviceConfig?.buzzerGpio ?? 0)
			self.hasChanges = false
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
	}
}
