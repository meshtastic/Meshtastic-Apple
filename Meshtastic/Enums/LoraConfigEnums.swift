//
//  LoraConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation
import MeshtasticProtobufs

enum RegionCodes: Int, CaseIterable, Identifiable {

	case unset = 0
	case us = 1
	case eu433 = 2
	case eu868 = 3
	case cn = 4
	case jp = 5
	case anz = 6
	case anz433 = 22
	case kr = 7
	case tw = 8
	case ru = 9
	case `in` = 10
	case nz865 = 11
	case th = 12
	case ua433 = 14
	case ua868 = 15
	case my433 = 16
	case my919 = 17
	case sg923 = 18
	case ph433 = 19
	case ph868 = 20
	case ph915 = 21
	case kz433 = 23
	case kz863 = 24
	case lora24 = 13
	var topic: String {
		switch self {
		case .unset:
			"UNSET"
		case .us:
			"US"
		case .eu433:
			"EU_433"
		case .eu868:
			"EU_868"
		case .cn:
			"CN"
		case .jp:
			"JP"
		case .anz:
			"ANZ"
		case .anz433:
			"ANZ_433"
		case .kr:
			"KR"
		case .tw:
			"TW"
		case .ru:
			"RU"
		case .in:
			"IN"
		case .nz865:
			"NZ_865"
		case .th:
			"TH"
		case .ua433:
			"UA_433"
		case .ua868:
			"UA_868"
		case .my433:
			"MY_433"
		case .my919:
			"MY_919"
		case .sg923:
			"SG_923"
		case .ph433:
			"ph_433"
		case .ph868:
			"ph_868"
		case .ph915:
			"ph_915"
		case .kz433:
			"KZ_433"
		case .kz863:
			"KZ_863"
		case .lora24:
			"LORA_24"
		} }
	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .unset:
			return "Please set a region".localized
		case .us:
			return "United States".localized
		case .eu433:
			return "European Union 433MHz".localized
		case .eu868:
			return "European Union 868MHz".localized
		case .cn:
			return "China".localized
		case .jp:
			return "Japan".localized
		case .anz:
			return "Australia / New Zealand".localized
		case .anz433:
			return "Australia / New Zealand 433MHz".localized
		case .kr:
			return "Korea".localized
		case .tw:
			return "Taiwan".localized
		case .ru:
			return "Russia".localized
		case .in:
			return "India".localized
		case .nz865:
			return "New Zealand 865MHz".localized
		case .th:
			return "Thailand".localized
		case .ua433:
			return "Ukraine 433MHz".localized
		case .ua868:
			return "Ukraine 868MHz".localized
		case .my433:
			return "Malaysia 433MHz".localized
		case .my919:
			return "Malaysia 919MHz".localized
		case .sg923:
			return "Singapore 923MHz".localized
		case .ph433:
			return "Philippines 433MHz".localized
		case .ph868:
			return "Philippines 868MHz".localized
		case .ph915:
			return "Philippines 915MHz".localized
		case .kz433:
			return "Kazakhstan 433MHz".localized
		case .kz863:
			return "Kazakhstan 863MHz".localized
		case .lora24:
			return "2.4 Ghz".localized
		}
	}
	var dutyCycle: Int {
		switch self {
		case .unset:
			return 0
		case .us:
			return 100
		case .eu433:
			return 10
		case .eu868:
			return 10
		case .cn:
			return 100
		case .jp:
			return 100
		case .anz:
			return 100
		case .kr:
			return 100
		case .tw:
			return 100
		case .ru:
			return 100
		case .in:
			return 100
		case .nz865:
			return 100
		case .th:
			return 100
		case .ua433:
			return 10
		case .ua868:
			return 10
		case .lora24:
			return 100
		case .my433:
			return 100
		case .my919:
			return 100
		case .sg923:
			return 100
		case .ph433:
			return 100
		case .ph868:
			return 100
		case .ph915:
			return 100
		case .anz433:
			return 100
		case .kz433:
			return 100
		case .kz863:
			return 100
		}
	}
	var isCountry: Bool {
		switch self {
		case .unset:
			return false
		case .us:
			return true
		case .eu433:
			return false
		case .eu868:
			return false
		case .cn:
			return true
		case .jp:
			return true
		case .anz:
			return false
		case .kr:
			return true
		case .tw:
			return true
		case .ru:
			return true
		case .in:
			return true
		case .nz865:
			return true
		case .th:
			return true
		case .ua433:
			return true
		case .ua868:
			return true
		case .lora24:
			return false
		case .my433:
			return true
		case .my919:
			return true
		case .sg923:
			return true
		case .ph433:
			return true
		case .ph868:
			return true
		case .ph915:
			return true
		case .anz433:
			return false
		case .kz433:
			return true
		case .kz863:
			return true
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
		case .my433:
			return Config.LoRaConfig.RegionCode.my433
		case .my919:
			return Config.LoRaConfig.RegionCode.my919
		case .sg923:
			return Config.LoRaConfig.RegionCode.sg923
		case .ph433:
			return Config.LoRaConfig.RegionCode.ph433
		case .ph868:
			return Config.LoRaConfig.RegionCode.ph868
		case .ph915:
			return Config.LoRaConfig.RegionCode.ph915
		case .anz433:
			return Config.LoRaConfig.RegionCode.anz433
		case .kz433:
			return Config.LoRaConfig.RegionCode.kz433
		case .kz863:
			return Config.LoRaConfig.RegionCode.kz863
		}
	}
}

enum ModemPresets: Int, CaseIterable, Identifiable {

	case longFast = 0
	case longSlow = 1
	case longModerate = 7
	case medSlow = 3
	case medFast = 4
	case shortSlow = 5
	case shortFast = 6
	case shortTurbo = 8

	var id: Int { self.rawValue }
	var description: String {
    		switch self {
		case .longFast:
			return "Long Range - Fast".localized
		case .longSlow:
			return "Long Range - Slow".localized
		case .longModerate:
			return "Long Range - Moderate".localized
		case .medSlow:
			return "Medium Range - Slow".localized
		case .medFast:
			return "Medium Range - Fast".localized
		case .shortSlow:
			return "Short Range - Slow".localized
		case .shortFast:
			return "Short Range - Fast".localized
		case .shortTurbo:
			return "Short Range - Turbo".localized
		}
	}
	var name: String {
		switch self {
		case .longFast:
			return "LongFast"
		case .longSlow:
			return "LongSlow"
		case .longModerate:
			return "LongModerate"
		case .medSlow:
			return "MediumSlow"
		case .medFast:
			return "MediumFast"
		case .shortSlow:
			return "ShortSlow"
		case .shortFast:
			return "ShortFast"
		case .shortTurbo:
			return "ShortTurbo"
		}
	}
	func snrLimit() -> Float {
		switch self {
		case .longFast:
			return -17.5
		case .longSlow:
			return -7.5
		case .longModerate:
			return -17.5
		case .medSlow:
			return -15
		case .medFast:
			return -12.5
		case .shortSlow:
			return -10
		case .shortFast:
			return -7.5
		case .shortTurbo:
			return -7.5
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
		case .medSlow:
			return Config.LoRaConfig.ModemPreset.mediumSlow
		case .medFast:
			return Config.LoRaConfig.ModemPreset.mediumFast
		case .shortSlow:
			return Config.LoRaConfig.ModemPreset.shortSlow
		case .shortFast:
			return Config.LoRaConfig.ModemPreset.shortFast
		case .shortTurbo:
			return Config.LoRaConfig.ModemPreset.shortTurbo
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
