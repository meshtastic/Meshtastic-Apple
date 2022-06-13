//
//  DeviceSettings.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/7/22.
//

import SwiftUI

enum GpsFormat: Int, CaseIterable, Identifiable {

	case gpsFormatDec = 0
	case gpsFormatDms = 1
	case gpsFormatUtm = 2
	case gpsFormatMgrs = 3
	case gpsFormatOlc = 4
	case gpsFormatOsgr = 5

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .gpsFormatDec:
				return "Decimal Degrees Format"
			case .gpsFormatDms:
				return "Degrees Minutes Seconds"
			case .gpsFormatUtm:
				return "Universal Transverse Mercator"
			case .gpsFormatMgrs:
				return "Military Grid Reference System"
			case .gpsFormatOlc:
				return "Open Location Code (aka Plus Codes)"
			case .gpsFormatOsgr:
				return "Ordnance Survey Grid Reference"
			}
		}
	}
}

// Default of 0 is One Minute
enum ScreenOnSeconds: Int, CaseIterable, Identifiable {

	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 0
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case max = 2147483647

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .fifteenSeconds:
				return "Fifteen Seconds"
			case .thirtySeconds:
				return "Thirty Seconds"
			case .oneMinute:
				return "One Minute"
			case .fiveMinutes:
				return "Five Minutes"
			case .tenMinutes:
				return "Ten Minutes"
			case .fifteenMinutes:
				return "Fifteen Minutes"
			case .max:
				return "Always On"
			}
		}
	}
}

// Default of 0 is off
enum ScreenCarouselSeconds: Int, CaseIterable, Identifiable {

	case off = 0
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .off:
				return "Off"
			case .fifteenSeconds:
				return "Fifteen Seconds"
			case .thirtySeconds:
				return "Thirty Seconds"
			case .oneMinute:
				return "One Minute"
			case .fiveMinutes:
				return "Five Minutes"
			case .tenMinutes:
				return "Ten Minutes"
			case .fifteenMinutes:
				return "Fifteen Minutes"
			}
		}
	}
}

struct DisplayConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@State var screenOnSeconds = 0
	@State var screenCarouselInterval = 0
	@State var gpsFormat = 0
	
	var body: some View {
		
		VStack {

			Form {
				Section(header: Text("Timing")) {
					
					Picker("Screen on for", selection: $screenOnSeconds ) {
						ForEach(ScreenOnSeconds.allCases) { sos in
							Text(sos.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Text("The number of seconds the screen remains on after the user button is pressed or messages are received.")
						.font(.caption)
						.listRowSeparator(.visible)
					
					Picker("Carousel Interval", selection: $screenCarouselInterval ) {
						ForEach(ScreenCarouselSeconds.allCases) { scs in
							Text(scs.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Text("Automatically toggles to the next page on the screen like a carousel, based the specified interval.")
						.font(.caption)
						.listRowSeparator(.visible)

				}
				Section(header: Text("Format")) {
					Picker("GPS Format", selection: $gpsFormat ) {
						ForEach(GpsFormat.allCases) { lu in
							Text(lu.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Text("The format used to display GPS coordinates on the screen.")
						.font(.caption)
						.listRowSeparator(.visible)
				}
			}
		}
		.navigationTitle("Display Config")
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
