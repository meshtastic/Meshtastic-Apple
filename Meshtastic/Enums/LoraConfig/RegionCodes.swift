//
//  RegionCodes.swift
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
    case np865 = 25
    case br902 = 26
    case itu12M = 27
    case itu232M = 28
    case eu866 = 29
    case eu874 = 30
    case eu917 = 31
    case euN868 = 32
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
        case .np865:
            "NP_865"
        case .br902:
            "BR_902"
        case .itu12M:
            "ITU1_2M"
        case .itu232M:
            "ITU23_2M"
        case .eu866:
            "EU_866"
        case .eu874:
            "EU_874"
        case .eu917:
            "EU_917"
        case .euN868:
            "EU_N_868"
        case .lora24:
            "LORA_24"
        }
    }

    var id: Int { self.rawValue }

    var description: String {
        switch self {
        case .unset:
            "Please set a region".localized
        case .us:
            "United States".localized
        case .eu433:
            "European Union 433MHz".localized
        case .eu868:
            "European Union 868MHz".localized
        case .cn:
            "China".localized
        case .jp:
            "Japan".localized
        case .anz:
            "Australia / New Zealand".localized
        case .anz433:
            "Australia / New Zealand 433MHz".localized
        case .kr:
            "Korea".localized
        case .tw:
            "Taiwan".localized
        case .ru:
            "Russia".localized
        case .in:
            "India".localized
        case .nz865:
            "New Zealand 865MHz".localized
        case .th:
            "Thailand".localized
        case .ua433:
            "Ukraine 433MHz".localized
        case .ua868:
            "Ukraine 868MHz".localized
        case .my433:
            "Malaysia 433MHz".localized
        case .my919:
            "Malaysia 919MHz".localized
        case .sg923:
            "Singapore 923MHz".localized
        case .ph433:
            "Philippines 433MHz".localized
        case .ph868:
            "Philippines 868MHz".localized
        case .ph915:
            "Philippines 915MHz".localized
        case .kz433:
            "Kazakhstan 433MHz".localized
        case .kz863:
            "Kazakhstan 863MHz".localized
        case .np865:
            "Nepal 865MHz".localized
        case .br902:
            "Brazil 902MHz".localized
        case .itu12M:
            "ITU Region 1 / Amateur 2m".localized
        case .itu232M:
            "ITU Region 2 & 3 / Amateur 2m".localized
        case .eu866:
            "European Union 866MHz".localized
        case .eu874:
            "European Union 874MHz".localized
        case .eu917:
            "European Union 917MHz".localized
        case .euN868:
            "European Union 868MHz (Narrow)".localized
        case .lora24:
            "2.4 Ghz".localized
        }
    }

    var dutyCycle: Int {
        switch self {
        case .unset:
            0
        case .us:
            100
        case .eu433:
            10
        case .eu868:
            10
        case .cn:
            100
        case .jp:
            100
        case .anz:
            100
        case .kr:
            100
        case .tw:
            100
        case .ru:
            100
        case .in:
            100
        case .nz865:
            100
        case .th:
            100
        case .ua433:
            10
        case .ua868:
            10
        case .lora24:
            100
        case .my433:
            100
        case .my919:
            100
        case .sg923:
            100
        case .ph433:
            100
        case .ph868:
            100
        case .ph915:
            100
        case .anz433:
            100
        case .kz433:
            100
        case .kz863:
            100
        case .np865:
            100
        case .br902:
            100
        case .itu12M:
            100
        case .itu232M:
            100
        case .eu866:
            10
        case .eu874:
            10
        case .eu917:
            10
        case .euN868:
            10
        }
    }

    var isCountry: Bool {
        switch self {
        case .unset:
            false
        case .us:
            true
        case .eu433:
            false
        case .eu868:
            false
        case .cn:
            true
        case .jp:
            true
        case .anz:
            false
        case .kr:
            true
        case .tw:
            true
        case .ru:
            true
        case .in:
            true
        case .nz865:
            true
        case .th:
            true
        case .ua433:
            true
        case .ua868:
            true
        case .lora24:
            false
        case .my433:
            true
        case .my919:
            true
        case .sg923:
            true
        case .ph433:
            true
        case .ph868:
            true
        case .ph915:
            true
        case .anz433:
            false
        case .kz433:
            true
        case .kz863:
            true
        case .np865:
            true
        case .br902:
            true
        case .itu12M:
            false
        case .itu232M:
            false
        case .eu866:
            false
        case .eu874:
            false
        case .eu917:
            false
        case .euN868:
            false
        }
    }

    func protoEnumValue() -> Config.LoRaConfig.RegionCode {
        switch self {
        case .unset:
            Config.LoRaConfig.RegionCode.unset
        case .us:
            Config.LoRaConfig.RegionCode.us
        case .eu433:
            Config.LoRaConfig.RegionCode.eu433
        case .eu868:
            Config.LoRaConfig.RegionCode.eu868
        case .cn:
            Config.LoRaConfig.RegionCode.cn
        case .jp:
            Config.LoRaConfig.RegionCode.jp
        case .anz:
            Config.LoRaConfig.RegionCode.anz
        case .kr:
            Config.LoRaConfig.RegionCode.kr
        case .tw:
            Config.LoRaConfig.RegionCode.tw
        case .ru:
            Config.LoRaConfig.RegionCode.ru
        case .in:
            Config.LoRaConfig.RegionCode.in
        case .nz865:
            Config.LoRaConfig.RegionCode.nz865
        case .th:
            Config.LoRaConfig.RegionCode.th
        case .ua433:
            Config.LoRaConfig.RegionCode.ua433
        case .ua868:
            Config.LoRaConfig.RegionCode.ua868
        case .lora24:
            Config.LoRaConfig.RegionCode.lora24
        case .my433:
            Config.LoRaConfig.RegionCode.my433
        case .my919:
            Config.LoRaConfig.RegionCode.my919
        case .sg923:
            Config.LoRaConfig.RegionCode.sg923
        case .ph433:
            Config.LoRaConfig.RegionCode.ph433
        case .ph868:
            Config.LoRaConfig.RegionCode.ph868
        case .ph915:
            Config.LoRaConfig.RegionCode.ph915
        case .anz433:
            Config.LoRaConfig.RegionCode.anz433
        case .kz433:
            Config.LoRaConfig.RegionCode.kz433
        case .kz863:
            Config.LoRaConfig.RegionCode.kz863
        case .np865:
            Config.LoRaConfig.RegionCode.np865
        case .br902:
            Config.LoRaConfig.RegionCode.br902
        case .itu12M:
            Config.LoRaConfig.RegionCode.itu12M
        case .itu232M:
            Config.LoRaConfig.RegionCode.itu232M
        case .eu866:
            Config.LoRaConfig.RegionCode.eu866
        case .eu874:
            Config.LoRaConfig.RegionCode.eu874
        case .eu917:
            Config.LoRaConfig.RegionCode.eu917
        case .euN868:
            Config.LoRaConfig.RegionCode.euN868
        }
    }
}
