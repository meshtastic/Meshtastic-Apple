//
//  DeviceSettings.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/7/22.
//

import SwiftUI

enum GpsFormats: Int, CaseIterable, Identifiable {

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
	func protoEnumValue() -> Config.DisplayConfig.GpsCoordinateFormat {
		
		switch self {
			
		case .gpsFormatDec:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatDec
		case .gpsFormatDms:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatDms
		case .gpsFormatUtm:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatUtm
		case .gpsFormatMgrs:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatMgrs
		case .gpsFormatOlc:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatOlc
		case .gpsFormatOsgr:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatOsgr
		}
	}
}

// Default of 0 is One Minute
enum ScreenOnIntervals: Int, CaseIterable, Identifiable {

	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 0
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case max = 31536000 // One Year

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .oneMinute:
				return "One Minute"
			case .fiveMinutes:
				return "Five Minutes"
			case .tenMinutes:
				return "Ten Minutes"
			case .fifteenMinutes:
				return "Fifteen Minutes"
			case .thirtyMinutes:
				return "Thirty Minutes"
			case .oneHour:
				return "One Hour"
			case .max:
				return "Always On"
			}
		}
	}
}

// Default of 0 is off
enum ScreenCarouselIntervals: Int, CaseIterable, Identifiable {

	case off = 0
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
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges = false

	@State var screenOnSeconds = 0
	@State var screenCarouselInterval = 0
	@State var gpsFormat = 0
	@State var compassNorthTop = false
	
	var body: some View {
		
		VStack {

			Form {
				Section(header: Text("Device Screen")) {
					
					Picker("Screen on for", selection: $screenOnSeconds ) {
						ForEach(ScreenOnIntervals.allCases) { soi in
							Text(soi.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Text("How long the screen remains on after the user button is pressed or messages are received.")
						.font(.caption)
					
					Picker("Carousel Interval", selection: $screenCarouselInterval ) {
						ForEach(ScreenCarouselIntervals.allCases) { sci in
							Text(sci.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Text("Automatically toggles to the next page on the screen like a carousel, based the specified interval.")
						.font(.caption)
					
					Toggle(isOn: $compassNorthTop) {

						Label("Always point north", systemImage: "location.north.circle")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					Text("The compass heading on the screen outside of the circle will always point north.")
						.font(.caption)
					
				}
				Section(header: Text("Format")) {
					Picker("GPS Format", selection: $gpsFormat ) {
						ForEach(GpsFormats.allCases) { lu in
							Text(lu.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Text("The format used to display GPS coordinates on the device screen.")
						.font(.caption)
						.listRowSeparator(.visible)
				}
			}
			.disabled(bleManager.connectedPeripheral == nil)
			
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
				Button("Save Display Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
					
					var dc = Config.DisplayConfig()
					dc.gpsFormat = GpsFormats(rawValue: gpsFormat)!.protoEnumValue()
					dc.screenOnSecs = UInt32(screenOnSeconds)
					dc.autoScreenCarouselSecs = UInt32(screenCarouselInterval)
					dc.compassNorthTop = compassNorthTop
					
					let adminMessageId =  bleManager.saveDisplayConfig(config: dc, fromUser: node!.user!, toUser: node!.user!, wantAck: true)
					
					if adminMessageId > 0 {
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						
					} else {
						
					}
				}
			}
		}
		.navigationTitle("Display Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			if self.initialLoad{
				
				self.bleManager.context = context

				self.gpsFormat = Int(node!.displayConfig?.gpsFormat ?? 0)
				self.screenOnSeconds = Int(node!.displayConfig?.screenOnSeconds ?? 0)
				self.screenCarouselInterval = Int(node!.displayConfig?.screenCarouselInterval ?? 0)
				self.compassNorthTop = node!.displayConfig?.compassNorthTop ?? false
				self.hasChanges = false
				self.initialLoad = false
			}
		}
		.onChange(of: screenOnSeconds) { newScreenSecs in
			
			if node != nil && node!.displayConfig != nil {
				
				if newScreenSecs != node!.displayConfig!.screenOnSeconds { hasChanges = true }
			}
		}
		.onChange(of: screenCarouselInterval) { newCarouselSecs in
			
			if node != nil && node!.displayConfig != nil {
				
				if newCarouselSecs != node!.displayConfig!.screenCarouselInterval { hasChanges = true }
			}
		}
		.onChange(of: compassNorthTop) { newCompassNorthTop in
			
			if node != nil && node!.displayConfig != nil {
				
				if newCompassNorthTop != node!.displayConfig!.compassNorthTop { hasChanges = true }
			}
		}
		.onChange(of: gpsFormat) { newGpsFormat in
			
			if node != nil && node!.displayConfig != nil {
			
				if newGpsFormat != node!.displayConfig!.gpsFormat { hasChanges = true }
			}
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
