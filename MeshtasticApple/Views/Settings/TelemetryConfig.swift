//
//  TelemetryConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/13/22.
//
import SwiftUI

struct TelemetryConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State var isPowerSaving = false
	@State var isAlwaysPowered = false
	
	var body: some View {
		
		VStack {

			Form {
				
			}
			.navigationTitle("Telemetry Config")
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
}
