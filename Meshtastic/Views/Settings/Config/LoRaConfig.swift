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
	case nz865 = 11
	case th = 12

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .unset:
				return "Please set a region"
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
	case MedSlow = 3
	case MedFast = 4
	case ShortSlow = 5
	case ShortFast = 6
	
	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
				
			case .LongFast:
				return "Long Range - Fast"
			case .LongSlow:
				return "Long Range - Slow"
			case .VLongSlow:
				return "Very Long Range - Slow"
			case .MedSlow:
				return "Medium Range - Slow"
			case .MedFast:
				return "Medium Range - Fast"
			case .ShortSlow:
				return "Short Range - Slow"
			case .ShortFast:
				return "Short Range - Fast"
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
			case .MedSlow:
				return Config.LoRaConfig.ModemPreset.medSlow
			case .MedFast:
				return Config.LoRaConfig.ModemPreset.medFast
			case .ShortSlow:
				return Config.LoRaConfig.ModemPreset.shortSlow
			case .ShortFast:
				return Config.LoRaConfig.ModemPreset.shortFast
			
		}
	}
}

enum HopValues : Int, CaseIterable, Identifiable {
	
	case oneHop = 1
	case twoHops = 2
	case threeHops = 0
	case fourHops = 4
	case fiveHops = 5
	case sixHops = 6
	case sevenHops = 7
	
	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
				
			case .oneHop:
				return "One Hop"
			case .twoHops:
				return "Two Hops"
			case .threeHops:
				return "Three Hops"
			case .fourHops:
				return "Four Hops"
			case .fiveHops:
				return "Five Hops"
			case .sixHops:
				return "Six Hops"
			case .sevenHops:
				return "Seven Hops"
			}
		}
	}
}

struct LoRaConfig: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	
	var node: NodeInfoEntity?
	
	@State var isPresentingSaveConfirm = false
	@State var initialLoad = true
	@State var hasChanges = false
	
	@State var region = 0
	@State var modemPreset  = 0
	@State var hopLimit  = 0
	@State var txPower  = 0
	
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
					Text("The region where you will be using your radios.")
						.font(.caption)
				}
				Section(header: Text("Modem")) {
					Picker("Presets", selection: $modemPreset ) {
						ForEach(ModemPresets.allCases) { m in
							Text(m.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Available modem presets, default is Long Fast.")
						.font(.caption)
				}
				Section(header: Text("Mesh Options")) {
					
					Picker("Number of hops", selection: $hopLimit) {
						ForEach(HopValues.allCases) { hop in
							Text(hop.description)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text("Sets the maximum number of hops, default is 3. Increasing hops also increases air time utilization and should be used carefully.")
						.font(.caption)
				}
			}
			.disabled(self.bleManager.connectedPeripheral == nil)
			
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
				Button("Save LoRa Config to \(bleManager.connectedPeripheral != nil ? bleManager.connectedPeripheral.longName : "Unknown")?") {
					
					var lc = Config.LoRaConfig()
					lc.hopLimit = UInt32(hopLimit)
					lc.region = RegionCodes(rawValue: region)!.protoEnumValue()
					lc.modemPreset = ModemPresets(rawValue: modemPreset)!.protoEnumValue()
					
					let adminMessageId = bleManager.saveLoRaConfig(config: lc, fromUser: node!.user!, toUser: node!.user!)
					
					if adminMessageId > 0 {
						
						// Should show a saved successfully alert once I know that to be true
						// for now just disable the button after a successful save
						hasChanges = false
						
					} else {
						
					}
				}
			}

		}
		.navigationTitle("LoRa Config")
		.navigationBarItems(trailing:

			ZStack {

			ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName : "????")
		})
		.onAppear {
			
			self.bleManager.context = context

			if self.initialLoad{
				
			
				self.hopLimit = Int(node!.loRaConfig?.hopLimit ?? 0)
				self.region = Int(node!.loRaConfig?.regionCode ?? 0)
				self.modemPreset = Int(node!.loRaConfig?.modemPreset ?? 0)
				self.txPower = Int(node!.loRaConfig?.txPower ?? 0)
				self.hasChanges = false
				self.initialLoad = false
			}
		}
		.onChange(of: region) { newRegion in
			
			if node != nil && node!.loRaConfig != nil {
				
				if newRegion != node!.loRaConfig!.regionCode { hasChanges = true }
			}
		}
		.onChange(of: modemPreset) { newModemPreset in
			
			if node != nil && node!.loRaConfig != nil {
				
				if newModemPreset != node!.loRaConfig!.modemPreset { hasChanges = true }
			}
		}
		.onChange(of: hopLimit) { newHopLimit in
			
			if node != nil && node!.loRaConfig != nil {
				
				if newHopLimit != node!.loRaConfig!.hopLimit { hasChanges = true }
			}
		}
		.navigationViewStyle(StackNavigationViewStyle())
	}
}
