//
//  PositionConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) Garth Vander Houwen 6/11/22.
//

import SwiftUI

enum GpsUpdateIntervals: Int, CaseIterable, Identifiable {

	case thirtySeconds = 0
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case maxInt32 = 2147483647

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {

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
			case .thirtyMinutes:
				return "Thirty Minutes"
			case .oneHour:
				return "One Hour"
			case .maxInt32:
				return "On Boot Only"
			}
		}
	}
}

enum GpsAttemptTimes: Int, CaseIterable, Identifiable {

	case thirtySeconds = 0
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {

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

enum PositionBroadcastIntervals: Int, CaseIterable, Identifiable {

	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 0
	case thirtyMinutes = 1800
	case oneHour = 3600

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {

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
			case .thirtyMinutes:
				return "Thirty Minutes"
			case .oneHour:
				return "One Hour"
			}
		}
	}
}

struct PositionConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity?
	
	@State private var isPresentingSaveConfirm: Bool = false
	@State var initialLoad: Bool = true
	@State var hasChanges = false
	
	@State var smartPositionEnabled = true
	@State var deviceGpsEnabled = true
	@State var fixedPosition = false
	@State var gpsUpdateInterval = 0
	@State var gpsAttemptTime = 0
	@State var positionBroadcastSeconds = 0
	
	/// Position Flags
	/// Altitude value - 1
	@State var includePosAltitude = true
	/// Altitude value is MSL - 2
	@State var includePosAltMsl = false
	/// Include geoidal separation - 4
	@State var includePosGeoSep = false
	/// Include the DOP value ; PDOP used by default, see below - 8
	@State var includePosDop = false
	/// If POS_DOP set, send separate HDOP / VDOP values instead of PDOP - 16
	@State var includePosHvdop = false
	/// Include number of "satellites in view" - 32
	@State var includePosSatsinview = false
	/// Include a sequence number incremented per packet - 64
	@State var includePosSeqNos = false
	/// Include positional timestamp (from GPS solution) - 128
	@State var includePosTimestamp = true
	/// Include positional heading - 256
	/// Intended for use with vehicle not walking speeds
	/// walking speeds are likely to be error prone like the compass
	@State var includePosSpeed = false
	/// Include positional speed - 512
	/// Intended for use with vehicle not walking speeds
	/// walking speeds are likely to be error prone like the compass
	@State var includePosHeading = false
	
	var body: some View {
		
		VStack {

			Form {

				Section(header: Text("Device GPS")) {
					
					Toggle(isOn: $deviceGpsEnabled) {

						Label("Device GPS Enabled", systemImage: "location")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					if deviceGpsEnabled {
											
						Picker("Update Interval", selection: $gpsUpdateInterval) {
							ForEach(GpsUpdateIntervals.allCases) { ui in
								Text(ui.description)
							}
						}
						.pickerStyle(DefaultPickerStyle())
						
						Text("How often should we try to get a GPS position.")
							.font(.caption)
							.listRowSeparator(.visible)
						
						Picker("Attempt Time", selection: $gpsAttemptTime) {
							ForEach(GpsAttemptTimes.allCases) { at in
								Text(at.description)
							}
						}
						.pickerStyle(DefaultPickerStyle())
						
						Text("How long should we try to get our position during each GPS Update Interval attempt?")
							.font(.caption)
							.listRowSeparator(.visible)

						
					} else {
						
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
				}
				
				Section(header: Text("Position Packet")) {
					
					Toggle(isOn: $smartPositionEnabled) {

						Label("Smart Position Broadcast", systemImage: "location.fill.viewfinder")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						
					Picker("Position Broadcast Interval", selection: $positionBroadcastSeconds) {
						ForEach(PositionBroadcastIntervals.allCases) { at in
							Text(at.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					
					Text("We should send our position this often (but only if it has changed significantly)")
						.font(.caption)
				}
				Section(header: Text("Position Flags - Non Functional")) {
					
					Text("Optional fields to include when assembling position messages. the more fields are included, the larger the message will be - leading to longer airtime and a higher risk of packet loss")
						.font(.caption)
						.listRowSeparator(.visible)
					
					Toggle(isOn: $includePosAltitude) {

						Label("Altitude", systemImage: "arrow.up")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $includePosSatsinview) {

						Label("Number of satellites", systemImage: "skew")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $includePosSeqNos) { //64

						Label("Sequence number", systemImage: "number")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $includePosTimestamp) { //128

						Label("Timestamp", systemImage: "clock")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $includePosHeading) { //128

						Label("Vehicle heading", systemImage: "location.circle")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $includePosSpeed) { //128

						Label("Vehicle speed", systemImage: "speedometer")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
				}
				Section(header: Text("Advanced Position Flags - Non Functional")) {
					
					Toggle(isOn: $includePosAltMsl) {

						Text("Altitude is MSL")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $includePosGeoSep) {

						Text("Geoidal Seperation")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $includePosDop) {

						Text("Dilution of precision (DOP) PDOP used by default")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					
					Toggle(isOn: $includePosHvdop) {

						Text("If DOP is set use, HDOP / VDOP values instead of PDOP")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
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
				isPresented: $isPresentingSaveConfirm,
				titleVisibility: .visible
			) {
				Button("Save Position Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
					
					var pc = Config.PositionConfig()
					pc.positionBroadcastSmartDisabled = !smartPositionEnabled
					pc.gpsDisabled = !deviceGpsEnabled
					pc.fixedPosition = fixedPosition
					pc.gpsUpdateInterval = UInt32(gpsUpdateInterval)
					pc.gpsAttemptTime = UInt32(gpsAttemptTime)
					pc.positionBroadcastSecs = UInt32(positionBroadcastSeconds)
					
					let adminMessageId =  bleManager.savePositionConfig(config: pc, fromUser: node!.user!, toUser: node!.user!, wantAck: true)
					
					if adminMessageId > 0{
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						
					} else {
						
					}
				}
			}
		}
		.navigationTitle("Position Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {

			if self.initialLoad{
				
				self.bleManager.context = context
				self.smartPositionEnabled = node!.positionConfig?.smartPositionEnabled ?? true
				self.deviceGpsEnabled = node!.positionConfig?.deviceGpsEnabled ?? true
				self.fixedPosition = node!.positionConfig?.fixedPosition ?? false
				self.gpsUpdateInterval = Int(node!.positionConfig?.gpsUpdateInterval ?? 0)
				self.gpsAttemptTime = Int(node!.positionConfig?.gpsAttemptTime ?? 0)
				self.positionBroadcastSeconds = Int(node!.positionConfig?.positionBroadcastSeconds ?? 0)
				self.hasChanges = false
				self.initialLoad = false
				
				self.includePosAltitude = true
				self.includePosTimestamp = true
				self.includePosSatsinview = true
			}
		}
		.onChange(of: smartPositionEnabled) { newSmartPosition in
			
			if node != nil && node!.positionConfig != nil {
				
				if newSmartPosition != node!.positionConfig!.smartPositionEnabled { hasChanges = true }
			}
		}
		.onChange(of: deviceGpsEnabled) { newDeviceGps in
			
			if node != nil && node!.positionConfig != nil {
				
				if newDeviceGps != node!.positionConfig!.deviceGpsEnabled { hasChanges = true }
			}
		}
		.onChange(of: fixedPosition) { newFixed in
			
			if node != nil && node!.positionConfig != nil {
			
				if newFixed != node!.positionConfig!.fixedPosition { hasChanges = true }
			}
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
