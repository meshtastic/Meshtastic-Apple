//
//  LoRaConfig.swift
//  Meshtastic Apple
//
//  Copyright (c) by Garth Vander Houwen 6/11/22.
//

import SwiftUI


enum RegionCodes : Int, CaseIterable, Identifiable {

	case unset = 0
	case us = 1
	case eu433 = 2
	case eu868 = 3
	case cn = 4
	case jp = 5
	case anz = 6
	case kr = 7
	case tw = 8
	case ru = 9
	//case in = 10
	case nz865
	case th

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .unset:
				return "UNSET - Please set a Region"
			case .us:
				return "United States"
			case .eu433:
				return "European Union 433mhz"
			case .eu868:
				return "European Union 868mhz"
			case .cn:
				return "China"
			case .jp:
				return "Japan"
			case .anz:
				return "Australia / New Zealand"
			case .kr:
				return "Korea"
			case .tw:
				return "Taiwan"
			case .ru:
				return "Russia"
			case .nz865:
				return "New Zealand 865mhz"
			case .th:
				return "TH"
			}
		}
	}
}

enum ModemPresets : Int, CaseIterable, Identifiable {
	
	case LongFast = 0
	case LongSlow = 1
	case VLongSlow = 2
	case MidSlow = 3
	case MidFast = 4
	case ShortSlow = 5
	case ShortFast = 6
	
	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
				
			case .LongFast:
				return "Long Fast"
			case .LongSlow:
				return "Long Slow"
			case .VLongSlow:
				return "Very Long Slow"
			case .MidSlow:
				return "Mid Slow"
			case .MidFast:
				return "Mid Fast"
			case .ShortSlow:
				return "Short Slow"
			case .ShortFast:
				return "Short Fast"
			}
		}
	}
}

struct LoRaConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State var region: Config.LoRaConfig.RegionCode = .us
	
	@State var modemPreset: Config.LoRaConfig.ModemPreset = .longFast
	
	var body: some View {
		
		VStack {

			Form {
				Section(header: Text("Region")) {
					
					Picker("Region", selection: $region ) {
						ForEach(RegionCodes.allCases) { r in
							Text(r.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("The region where you will be using your Meshtastic LoRa radios.")
						.font(.caption)
						.listRowSeparator(.visible)
					.listRowSeparator(.visible)
				}
				Section(header: Text("Modem")) {
					Picker("Presets", selection: $region ) {
						ForEach(ModemPresets.allCases) { m in
							Text(m.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Available modem presets.")
						.font(.caption)
						.listRowSeparator(.visible)
					.listRowSeparator(.visible)
				}
				
			}
			
		}
		.navigationTitle("LoRa Config")
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
