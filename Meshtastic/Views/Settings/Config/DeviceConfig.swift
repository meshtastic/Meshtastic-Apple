//
//  DeviceConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import SwiftUI

// Default of 0 is One Minute
enum DeviceRoles: Int, CaseIterable, Identifiable {

	case client = 0
	case clientMute = 1
	case router = 2
	case routerClient = 3

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			
			case .client:
				return "Client (default) - App connected client."
			case .clientMute:
				return "Client Mute - Same as a client except packets will not hop over this node, does not contribute to routing packets for mesh."
			case .router:
				return "Router -  Mesh packets will prefer to be routed over this node. This node will not be used by client apps. The wifi/ble radios and the oled screen will be put to sleep."
			case .routerClient:
				return "Router Client - Mesh packets will prefer to be routed over this node. The Router Client can be used as both a Router and an app connected Client."
			}
		}
	}
	func protoEnumValue() -> Config.DeviceConfig.Role {
		
		switch self {
			
		case .client:
			return Config.DeviceConfig.Role.client
		case .clientMute:
			return Config.DeviceConfig.Role.clientMute
		case .router:
			return Config.DeviceConfig.Role.router
		case .routerClient:
			return Config.DeviceConfig.Role.routerClient
		}
	}
}

struct DeviceConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity
	
	@State private var isPresentingFactoryResetConfirm: Bool = false
	@State private var isPresentingSaveConfirm: Bool = false
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
					
					"Are you sure?",
					isPresented: $isPresentingSaveConfirm
				) {
					Button("Save Device Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
						
						var dc = Config.DeviceConfig()
						dc.role = DeviceRoles(rawValue: deviceRole)!.protoEnumValue()
						dc.serialDisabled = !serialEnabled
						dc.debugLogEnabled = debugLogEnabled
						
						let adminMessageId = bleManager.saveDeviceConfig(config: dc, fromUser: node.user!, toUser: node.user!, wantResponse: true)
						
						if adminMessageId > 0 {
							
							// Should show a saved successfully alert once I know that to be true
							// for now just disable the button after a successful save
							hasChanges = false
							
						} else {
							
						}
					}
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
						
						if !bleManager.sendFactoryReset(destNum: bleManager.connectedPeripheral.num, wantResponse: false) {
							
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

				self.deviceRole = Int(node.deviceConfig?.role ?? 0)
				self.serialEnabled = (node.deviceConfig?.serialEnabled ?? true)
				self.debugLogEnabled = node.deviceConfig?.debugLogEnabled ?? false
				self.hasChanges = false
				self.initialLoad = false
			}
		}
		.onChange(of: deviceRole) { newRole in
			
			if newRole != node.deviceConfig!.role {
				
				hasChanges = true
			}
		}
		.onChange(of: serialEnabled) { newSerial in
			
			if newSerial != node.deviceConfig!.serialEnabled {
				
				hasChanges = true
			}
		}
		.onChange(of: debugLogEnabled) { newDebugLog in
			
			if newDebugLog != node.deviceConfig!.debugLogEnabled {
				
				hasChanges = true
			}
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
