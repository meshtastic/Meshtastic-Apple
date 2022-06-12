//
//  PowerConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/12/22.
//

import Foundation
import SwiftUI

enum ChargeCurrents: Int, CaseIterable, Identifiable {

	case maunset = 0
	case ma100 = 1
	case ma190 = 2
	case ma280 = 3
	case ma360 = 4
	case ma450 = 5
	case ma550 = 6
	case ma630 = 7
	case ma700 = 8
	case ma780 = 9
	case ma880 = 10
	case ma960 = 11
	case ma1000 = 12
	case ma1080 = 13
	case ma1160 = 14
	case ma1240 = 15
	case ma1320 = 16

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {

			case .maunset:
				return "UNSET (default)"
			case .ma100:
				return "100 mA"
			case .ma190:
				return "190 mA"
			case .ma280:
				return "280 mA"
			case .ma360:
				return "360 mA"
			case .ma450:
				return "450 mA"
			case .ma550:
				return "550 mA"
			case .ma630:
				return "630 mA"
			case .ma700:
				return "700 mA"
			case .ma780:
				return "780 mA"
			case .ma880:
				return "880 mA"
			case .ma960:
				return "960 mA"
			case .ma1000:
				return "1000 mA"
			case .ma1080:
				return "1080 mA"
			case .ma1160:
				return "1160 mA"
			case .ma1240:
				return "1240 mA"
			case .ma1320:
				return "1320 mA"
			}
		}
	}
}


struct PowerConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State var chargeCurrent = 0
	@State var deviceGpsEnabled = true
	@State var fixedPosition = false
	@State var gpsUpdateInterval: Int32 = 0
	@State var gpsAttemptTime: Int32 = 0
	@State var positionBroadcastSeconds: Int32 = 0
	
	var body: some View {
		
		VStack {

			Form {

				Section(header: Text("Charging Options")) {
					
					Picker("Charge Current", selection: $chargeCurrent) {
						ForEach(ChargeCurrents.allCases) { cc in
							Text(cc.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Text("Sets the charge control current of devices with a battery charger that can be configured. This is passed into the axp power management chip like on the tbeam.")
						.font(.caption)
						.listRowSeparator(.visible)
		
						
					Toggle(isOn: $fixedPosition) {

						Label("Fixed Position", systemImage: "location.square.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					if fixedPosition {
						
						Text("Set to current location here")
						.font(.caption)
						.listRowSeparator(.visible)
					}
				}
				Section(header: Text("Position Flags")) {
					Text("TODO")
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
