//
//  LoraConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation

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
			return Config.LoRaConfig.ModemPreset.veryLongSlow
			case .MedSlow:
			return Config.LoRaConfig.ModemPreset.mediumSlow
			case .MedFast:
				return Config.LoRaConfig.ModemPreset.mediumFast
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
	case threeHops = 3
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
