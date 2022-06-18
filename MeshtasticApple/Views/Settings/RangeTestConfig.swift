//
//  TelemetryConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import SwiftUI

struct RangeTestConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State var enabled = false
	@State var sender = false
	@State var save = false
	
	var body: some View {
		
		VStack {

			Form {
				
				Section(header: Text("Options")) {
				
					Toggle(isOn: $enabled) {

						Label("Enabled", systemImage: "figure.walk")
					}
					.toggleStyle(DefaultToggleStyle())
					.listRowSeparator(.visible)
					
					Toggle(isOn: $sender) {

						Label("Sender", systemImage: "paperplane")
					}
					.toggleStyle(DefaultToggleStyle())
					Text("This device will send out range test messages.")
						.font(.caption)
						.listRowSeparator(.visible)
					
					Toggle(isOn: $save) {

						Label("Save", systemImage: "square.and.arrow.down.fill")
					}
					.toggleStyle(DefaultToggleStyle())
					Text("Saves a CSV with the range test message details, only available on ESP32 devices with a web server.")
						.font(.caption)
						.listRowSeparator(.visible)
				}
					
			}
			.navigationTitle("Range Test Config")
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
