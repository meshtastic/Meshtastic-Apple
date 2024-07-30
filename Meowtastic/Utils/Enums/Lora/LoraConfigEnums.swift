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
	case lora24 = 13

	var id: Int {
		rawValue
	}

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

		case .lora24:
			"LORA_24"
		}
	}

	var description: String {
		switch self {
		case .unset:
			return "Not Set"

		case .us:
			return "USA"

		case .eu433:
			return "EU 433mHz"

		case .eu868:
			return "EU 868mHz"

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
			return "New Zealand 865mHz"

		case .th:
			return "Thailand"

		case .ua433:
			return "Ukraine 433mHz"

		case .ua868:
			return "Ukraine 868mHz"

		case .lora24:
			return "2.4 GHZ"

		case .my433:
			return "Malaysia 433mHz"

		case .my919:
			return "Malaysia 919mHz"

		case .sg923:
			return "Singapore 923mHz"
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
		}
	}
}
