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
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingFactoryResetConfirm = false
	@State private var isPresentingSaveConfirm = false
	@State var initialLoad: Bool = true
	@State var hasChanges = false
	
	@State var deviceRole = 0
	@State var serialEnabled = true
	@State var debugLogEnabled = false
	
	var body: some View {
			
		VStack {

			Form {
				
				Section(header: Text("Options")) {
					
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
			}
			.disabled(bleManager.connectedPeripheral == nil)
			
			HStack {
				
				Button {
								
					isPresentingSaveConfirm = true
					
				} label: {
					
					Label("Save", systemImage: "square.and.arrow.down")
				}
				.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.confirmationDialog(
					
					"Are you sure you want to save?",
					isPresented: $isPresentingSaveConfirm,
					titleVisibility: .visible
				) {
					Button("Save Device Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
						
						var dc = Config.DeviceConfig()
						dc.role = DeviceRoles(rawValue: deviceRole)!.protoEnumValue()
						dc.serialEnabled = serialEnabled
						dc.debugLogEnabled = debugLogEnabled
						
						let adminMessageId = bleManager.saveDeviceConfig(config: dc, fromUser: node!.user!, toUser: node!.user!)
						
						if adminMessageId > 0 {
							
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
							
						} else {
							
						}
					} 
				}
				message: {
					
					Text("After device config saves the node will reboot.")
				}
			
				Button("Factory Reset", role: .destructive) {
					
					isPresentingFactoryResetConfirm = true
				}
				.disabled(bleManager.connectedPeripheral == nil)
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
				.confirmationDialog(
					"Are you sure?",
					isPresented: $isPresentingFactoryResetConfirm
				) {
					Button("Erase all device settings?", role: .destructive) {
						
						if !bleManager.sendFactoryReset(destNum: bleManager.connectedPeripheral.num) {
							
							print("Factory Reset Failed")
						}
					}
				}
			}
			Spacer()
		}
		
		.navigationTitle("Device Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			if self.initialLoad{
				
				self.bleManager.context = context

				self.deviceRole = Int(node?.deviceConfig?.role ?? 0)
				self.serialEnabled = (node?.deviceConfig?.serialEnabled ?? true)
				self.debugLogEnabled = node?.deviceConfig?.debugLogEnabled ?? false
				self.hasChanges = false
				self.initialLoad = false
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
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
