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
				return "Client (default)"
			case .clientMute:
				return "Client Mute - Packets will not hop over this node, does not contribute to routing packets for mesh."
			case .router:
				return "Router - Mesh packets will prefer to be routed over this node. This node will not be used by client apps. The wifi/ble radios and the oled screen will be put to sleep."
			case .routerClient:
				return "Router Client - Mesh packets will prefer to be routed over this node. The Router Client can be used as both a Router and an app connected Client."
			}
		}
	}
}

struct DeviceConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@State var deviceRole = 0
	@State var serialEnabled = true
	@State var debugLogEnabled = false
	
	@State private var isPresentingFactoryResetConfirm: Bool = false
	
	var body: some View {
			
		VStack {

			Form {
				
				Section(header: Text("Options")) {
					
					Picker("Device Role", selection: $deviceRole ) {
						ForEach(DeviceRoles.allCases) { dr in
							Text(dr.description)
						}
					}
					.pickerStyle(InlinePickerStyle())
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
			Spacer()
		}
		
		.navigationTitle("Device Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?????")
		})
		.onAppear {

			self.bleManager.context = context
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
