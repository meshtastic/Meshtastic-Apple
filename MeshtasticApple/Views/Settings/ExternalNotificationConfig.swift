//
//  External Notification Config.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/22/22.
//
import SwiftUI

struct ExternalNotificationConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity
	
	@State var enabled = false
	@State var outputMilliseconds = 0
	@State var output = 0
	@State var active = false
	@State var alertMessage = false
	@State var alertBell = false
	
	var body: some View {
		
		VStack {

			Form {
				
				Section(header: Text("Options")) {
					
					Toggle(isOn: $enabled) {

						Label("Module Enabled", systemImage: "megaphone")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				
					Toggle(isOn: $alertBell) {

						Label("Alert when receiving a bell", systemImage: "bell")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $alertMessage) {

						Label("Alert when receiving a message", systemImage: "message")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					
				}
				
				Section(header: Text("GPIO")) {
					
					Toggle(isOn: $active) {

						Label("Active", systemImage: "togglepower")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("Specifies whether the external circuit is triggered when the device's GPIO is low or high.")
						.font(.caption)
						.listRowSeparator(.visible)
					
					Picker("GPIO to monitor", selection: $output) {
						ForEach(0..<25) {
							
							Text("\($0)")
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Specifies the GPIO that your external circuit is attached to on the device.")
						.font(.caption)
						.listRowSeparator(.visible)
					
				}
			}
			.navigationTitle("External Notification Config")
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
}
