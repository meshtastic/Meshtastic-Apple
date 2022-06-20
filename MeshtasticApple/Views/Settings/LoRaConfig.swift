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
	case `in` = 10
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
			case .in:
				return "India"
			case .nz865:
				return "New Zealand 865mhz"
			case .th:
				return "Thailand"
			}
		}
	}
	
	func protoEnumValue() -> Config.LoRaConfig.RegionCode {
		
		switch self {
		
			case .unset:
				return Config.LoRaConfig.RegionCode.unset
			case .us:
				return Config.LoRaConfig.RegionCode.us
			case .eu433:
				return Config.LoRaConfig.RegionCode.eu433
			case .eu868:
				return Config.LoRaConfig.RegionCode.eu868
			case .cn:
				return Config.LoRaConfig.RegionCode.cn
			case .jp:
				return Config.LoRaConfig.RegionCode.jp
			case .anz:
				return Config.LoRaConfig.RegionCode.anz
			case .kr:
				return Config.LoRaConfig.RegionCode.kr
			case .tw:
				return Config.LoRaConfig.RegionCode.tw
			case .ru:
				return Config.LoRaConfig.RegionCode.ru
			case .in:
				return Config.LoRaConfig.RegionCode.in
			case .nz865:
				return Config.LoRaConfig.RegionCode.nz865
			case .th:
				return Config.LoRaConfig.RegionCode.th
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
	func protoEnumValue() -> Config.LoRaConfig.ModemPreset {
		
		switch self {

			case .LongFast:
				return Config.LoRaConfig.ModemPreset.longFast
			case .LongSlow:
				return Config.LoRaConfig.ModemPreset.longSlow
			case .VLongSlow:
				return Config.LoRaConfig.ModemPreset.vlongSlow
			case .MidSlow:
				return Config.LoRaConfig.ModemPreset.midSlow
			case .MidFast:
				return Config.LoRaConfig.ModemPreset.midFast
			case .ShortSlow:
				return Config.LoRaConfig.ModemPreset.shortSlow
			case .ShortFast:
				return Config.LoRaConfig.ModemPreset.shortFast
			
		}
	}
}

struct LoRaConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	@State var region = 1
	@State var modemPreset  = 0
	@State var hopLimit  = 0
	@State var hasChanges = false
	
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
				Section(header: Text("Mesh Options")) {
					
					Picker("Number of hops", selection: $hopLimit) {
						ForEach(0..<8) {
							if $0 == 0 {
								Text("Default")
							} else {
								Text("\($0) Hops")
							}
						}
					}
					.pickerStyle(DefaultPickerStyle())
				}
			}
			
			Button {
							
				var lc = Config.LoRaConfig()
				lc.hopLimit = UInt32(hopLimit)
				lc.region = RegionCodes(rawValue: region)!.protoEnumValue()
				lc.modemPreset = ModemPresets(rawValue: modemPreset)!.protoEnumValue()
				
				if bleManager.saveLoRaConfig(config: lc, destNum: bleManager.connectedPeripheral.num, wantResponse: false) {
					
				} else {
					
				}
				
			} label: {
				Label("Save", systemImage: "square.and.arrow.down")
			}
			.disabled(bleManager.connectedPeripheral == nil || !hasChanges)
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()

		}
		.navigationTitle("LoRa Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "?????")
		})
		.onAppear {

			self.bleManager.context = context
		}
		.onChange(of: region) { newRegion in
			
			hasChanges = true
		}
		.onChange(of: modemPreset) { newModemPreset in
			
			hasChanges = true
		}
		.onChange(of: hopLimit) { newHopLimit in
			
			hasChanges = true
		}
		
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
