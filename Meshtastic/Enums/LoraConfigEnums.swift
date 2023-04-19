//
//  LoraConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation

enum RegionCodes: Int, CaseIterable, Identifiable {

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
	case ua433 = 14
	case ua868 = 15
	case lora24 = 13

	var id: Int { self.rawValue }
	var description: String {
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
		case .ua433:
			return "Ukraine 433mhz"
		case .ua868:
			return "Ukraine 868mhz"
		case .lora24:
			return "2.4 GHZ"
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
		case .ua433:
			return Config.LoRaConfig.RegionCode.ua433
		case .ua868:
			return Config.LoRaConfig.RegionCode.ua868
		case .lora24:
			return Config.LoRaConfig.RegionCode.lora24
		}
	}
}

enum ModemPresets: Int, CaseIterable, Identifiable {

	case longFast = 0
	case longSlow = 1
	case longModerate = 7
	case vLongSlow = 2
	case medSlow = 3
	case medFast = 4
	case shortSlow = 5
	case shortFast = 6

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .longFast:
			return "Long Range - Fast"
		case .longSlow:
			return "Long Range - Slow"
		case .longModerate:
			return "Long Range - Moderate"
		case .vLongSlow:
			return "Very Long Range - Slow"
		case .medSlow:
			return "Medium Range - Slow"
		case .medFast:
			return "Medium Range - Fast"
		case .shortSlow:
			return "Short Range - Slow"
		case .shortFast:
			return "Short Range - Fast"
		}
	}
	func protoEnumValue() -> Config.LoRaConfig.ModemPreset {
		switch self {
		case .longFast:
			return Config.LoRaConfig.ModemPreset.longFast
		case .longSlow:
			return Config.LoRaConfig.ModemPreset.longSlow
		case .longModerate:
			return Config.LoRaConfig.ModemPreset.longModerate
		case .vLongSlow:
			return Config.LoRaConfig.ModemPreset.veryLongSlow
		case .medSlow:
			return Config.LoRaConfig.ModemPreset.mediumSlow
		case .medFast:
			return Config.LoRaConfig.ModemPreset.mediumFast
		case .shortSlow:
			return Config.LoRaConfig.ModemPreset.shortSlow
		case .shortFast:
			return Config.LoRaConfig.ModemPreset.shortFast
		}
	}
}

enum Bandwidths: Int, CaseIterable, Identifiable {

	case thirtyOne = 31
	case sixtyTwo = 62
	case oneHundredTwentyFive = 125
	case twoHundredFifty = 250
	case fiveHundred = 500

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .thirtyOne:
			return "31 kHz"
		case .sixtyTwo:
			return "62 kHz"
		case .oneHundredTwentyFive:
			return "125 kHz"
		case .twoHundredFifty:
			return "250 kHz"
		case .fiveHundred:
			return "500 kHz"
		}
	}
}
