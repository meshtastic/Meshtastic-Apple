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
				
				Section(header: Text("Warning")) {
				
					Text("These power settings are designed for and and are only useful mostly for solar use cases. Do not use these settings if you are planning on using your device for messaging paired with a phone.")
						.font(.callout)
						.listRowSeparator(.visible)
				}
				Section(header: Text("States")) {
					
					Toggle(isOn: $isPowerSaving) {

						Label("Power Saving", systemImage: "powersleep")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.disabled(isAlwaysPowered)
					Text("If set, we are powered from a low-current source (i.e. solar) and do not intend on using a client to connect via BLE, WiFi or Serial.  This setting is assumed and unnessary if you have turned on Router mode.")
						.font(.caption)
						.listRowSeparator(.visible)
					
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
