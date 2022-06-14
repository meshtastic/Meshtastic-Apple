//
//  PowerConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/12/22.
//

import Foundation
import SwiftUI

struct PowerConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State var isPowerSaving = false
	@State var isAlwaysPowered = false
	
	var body: some View {
		
		VStack {

			Form {
				
				Section(header: Text("Enhanced Power Management")) {
				
					Text("Meshtastic devices have been improved with simplified role based power management.")
						.font(.callout)
						.listRowSeparator(.visible)
				}
				Section(header: Text("State")) {
					
					Toggle(isOn: $isAlwaysPowered) {

						Label("Always Powered", systemImage: "powerplug.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.disabled(isPowerSaving)
					Text("Circumvents the logic block for determining whether the device is powered or not. Useful for devices with finicky ADC issues on the battery sense pins, or no battery pin at all. This mode increases battery use substantially")
						.font(.caption)
						.listRowSeparator(.visible)

				}
			}
		}
		.navigationTitle("Power Config")
		.navigationBarItems(trailing:

			ZStack {

				ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.lastFourCode : "????")
		})
		.onAppear {

			self.bleManager.context = context
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
