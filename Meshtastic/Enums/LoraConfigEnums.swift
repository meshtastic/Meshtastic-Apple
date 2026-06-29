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
	case np865 = 25
	case br902 = 26
	case itu12M = 27
	case itu22M = 28
	case eu866 = 29
	case eu874 = 30
	case eu917 = 31
	case euN868 = 32
	case lora24 = 13
	case itu32M = 33
	case itu170Cm = 34
	case itu270Cm = 35
	case itu370Cm = 36
	case itu2125Cm = 37

	/// Regions reworked / added in the 2.8 firmware (amateur/ham bands and the
	/// EU SRD / narrow bands). Firmware older than 2.8 has no band table for
	/// these and would silently clamp the selection, so they must not be offered
	/// when connected to a 2.7.x-or-earlier device.
	var requiresFirmware2_8: Bool {
		switch self {
		case .eu866, .euN868, .itu12M, .itu22M, .itu32M, .itu170Cm, .itu270Cm, .itu370Cm, .itu2125Cm:
			return true
		default:
			return false
		}
	}

	/// Regions the firmware enumerates but the app does not yet surface in the
	/// picker (no firmware band table / not ready). Hidden on every firmware.
	var isHiddenFromPicker: Bool {
		switch self {
		case .eu874, .eu917:
			return true
		default:
			return false
		}
	}

	/// Regions selectable for a connected device, given whether its firmware
	/// implements the 2.8 region rework. On older firmware the 2.8-only regions
	/// are dropped so the user can't pick a value the radio doesn't understand.
	static func selectable(supports2_8: Bool) -> [RegionCodes] {
		allCases.filter { region in
			if region.isHiddenFromPicker { return false }
			if region.requiresFirmware2_8 && !supports2_8 { return false }
			return true
		}
	}

	/// The conservative (pre-2.8) selectable set. Retained for callers that have
	/// no connected-firmware context (e.g. the discovery scan preset list).
	static var userSelectable: [RegionCodes] {
		selectable(supports2_8: false)
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
		case .itu22M:
			"ITU2_2M"
		case .eu866:
			"EU_866"
		case .eu874:
			"EU_874"
		case .eu917:
			"EU_917"
		case .euN868:
			"EU_N_868"
		case .itu32M:
			"ITU3_2M"
		case .itu170Cm:
			"ITU1_70CM"
		case .itu270Cm:
			"ITU2_70CM"
		case .itu370Cm:
			"ITU3_70CM"
		case .itu2125Cm:
			"ITU2_125CM"
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
		case .np865:
			return "Nepal 865MHz".localized
		case .br902:
			return "Brazil 902MHz".localized
		case .itu12M:
			return "ITU Region 1 / Amateur 2m".localized
		case .itu22M:
			return "ITU Region 2 / Amateur 2m".localized
		case .eu866:
			return "European Union 866MHz".localized
		case .eu874:
			return "European Union 874MHz".localized
		case .eu917:
			return "European Union 917MHz".localized
		case .euN868:
			return "European Union 868MHz (Narrow)".localized
		case .itu32M:
			return "ITU Region 3 / Amateur 2m".localized
		case .itu170Cm:
			return "ITU Region 1 / Amateur 70cm".localized
		case .itu270Cm:
			return "ITU Region 2 / Amateur 70cm".localized
		case .itu370Cm:
			return "ITU Region 3 / Amateur 70cm".localized
		case .itu2125Cm:
			return "ITU Region 2 / Amateur 1.25m".localized
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
		case .np865:
			return 100
		case .br902:
			return 100
		case .itu12M:
			return 100
		case .itu22M:
			return 100
		case .eu866:
			return 10
		case .eu874:
			return 10
		case .eu917:
			return 10
		case .euN868:
			return 10
		case .itu32M:
			return 100
		case .itu170Cm:
			return 100
		case .itu270Cm:
			return 100
		case .itu370Cm:
			return 100
		case .itu2125Cm:
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
		case .np865:
			return true
		case .br902:
			return true
		case .itu12M:
			return false
		case .itu22M:
			return false
		case .eu866:
			return false
		case .eu874:
			return false
		case .eu917:
			return false
		case .euN868:
			return false
		case .itu32M:
			return false
		case .itu170Cm:
			return false
		case .itu270Cm:
			return false
		case .itu370Cm:
			return false
		case .itu2125Cm:
			return false
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
		case .np865:
			return Config.LoRaConfig.RegionCode.np865
		case .br902:
			return Config.LoRaConfig.RegionCode.br902
		case .itu12M:
			return Config.LoRaConfig.RegionCode.itu12M
		case .itu22M:
			return Config.LoRaConfig.RegionCode.itu22M
		case .eu866:
			return Config.LoRaConfig.RegionCode.eu866
		case .eu874:
			return Config.LoRaConfig.RegionCode.eu874
		case .eu917:
			return Config.LoRaConfig.RegionCode.eu917
		case .euN868:
			return Config.LoRaConfig.RegionCode.euN868
		case .itu32M:
			return Config.LoRaConfig.RegionCode.itu32M
		case .itu170Cm:
			return Config.LoRaConfig.RegionCode.itu170Cm
		case .itu270Cm:
			return Config.LoRaConfig.RegionCode.itu270Cm
		case .itu370Cm:
			return Config.LoRaConfig.RegionCode.itu370Cm
		case .itu2125Cm:
			return Config.LoRaConfig.RegionCode.itu2125Cm
		}
	}
}

enum ModemPresets: Int, CaseIterable, Identifiable {

	case longFast = 0
	case longSlow = 1
	case longModerate = 7
	case longTurbo = 9
	case medSlow = 3
	case medFast = 4
	case shortSlow = 5
	case shortFast = 6
	case shortTurbo = 8
	case liteFast = 10
	case liteSlow = 11
	case narrowFast = 12
	case narrowSlow = 13
	case tinyFast = 14
	case tinySlow = 15

	/// Presets added in the 2.8 firmware: Lite (125 kHz), Narrow (62.5 kHz) and
	/// Tiny (20 kHz, ham). Firmware older than 2.8 does not implement them, so
	/// they must not be offered when connected to a 2.7.x-or-earlier device.
	/// They still exist as cases so a radio already configured on one of them
	/// round-trips through protobuf and renders the correct label in node lists.
	var requiresFirmware2_8: Bool {
		switch self {
		case .liteFast, .liteSlow, .narrowFast, .narrowSlow, .tinyFast, .tinySlow:
			return true
		default:
			return false
		}
	}

	/// Presets selectable for a connected device, given whether its firmware
	/// implements the 2.8 rework. On older firmware the 2.8-only presets are
	/// dropped. Callers should additionally constrain this to the selected
	/// region's legal set via `RegionPresetInfo` when the firmware provides one.
	static func selectable(supports2_8: Bool) -> [ModemPresets] {
		allCases.filter { supports2_8 || !$0.requiresFirmware2_8 }
	}

	/// The conservative (pre-2.8) selectable set. Retained for callers that have
	/// no connected-firmware context (e.g. the discovery scan preset list).
	static var userSelectable: [ModemPresets] {
		selectable(supports2_8: false)
	}

	/// Decides which modem preset to pre-select when the region changes, given the
	/// firmware's advertised compatibility info for that region. Returns `nil` to
	/// keep the current selection. Pure (no view state) so it can be unit-tested.
	///
	/// Rules, in order:
	/// 1. Only acts on 2.8 firmware with `usePreset` on; otherwise keep current.
	/// 2. A factory-flashed node (region not yet configured) defaults to
	///    `longTurbo` when **US** is selected, provided Long Turbo is legal there.
	/// 3. Otherwise, if the current preset is not legal in the region, fall back to
	///    that region's advertised default. A legal current preset is kept.
	static func presetToSelect(
		forRegion region: Config.LoRaConfig.RegionCode,
		factoryFresh: Bool,
		supports2_8: Bool,
		usePreset: Bool,
		regionInfo: RegionPresetInfo?,
		currentPreset: ModemPresets?
	) -> ModemPresets? {
		guard supports2_8, usePreset else { return nil }

		if factoryFresh, region == .us,
		   regionInfo == nil || regionInfo?.presets.contains(.longTurbo) == true {
			return .longTurbo
		}

		guard let info = regionInfo, !info.presets.isEmpty,
			  let current = currentPreset else { return nil }
		if info.presets.contains(current.protoEnumValue()) { return nil }
		return ModemPresets(rawValue: info.defaultPreset.rawValue)
	}

	var id: Int { self.rawValue }
	var description: String {
    		switch self {
		case .longFast:
			return "Long Range - Fast".localized
		case .longSlow:
			return "Long Range - Slow".localized
		case .longModerate:
			return "Long Range - Moderate".localized
		case .longTurbo:
			return "Long Range - Turbo".localized
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
		case .liteFast:
			return "Lite - Fast".localized
		case .liteSlow:
			return "Lite - Slow".localized
		case .narrowFast:
			return "Narrow - Fast".localized
		case .narrowSlow:
			return "Narrow - Slow".localized
		case .tinyFast:
			return "Tiny - Fast".localized
		case .tinySlow:
			return "Tiny - Slow".localized
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
		case .longTurbo:
			return "LongTurbo"
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
		case .liteFast:
			return "LiteFast"
		case .liteSlow:
			return "LiteSlow"
		case .narrowFast:
			return "NarrowFast"
		case .narrowSlow:
			return "NarrowSlow"
		case .tinyFast:
			return "TinyFast"
		case .tinySlow:
			return "TinySlow"
		}
	}
	func snrLimit() -> Float {
		switch self {
		case .longFast:
			return -17.5
		case .longSlow:
			return -7.5
		case .longTurbo:
			return -12.5
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
		case .liteFast:
			// Lite presets are 125kHz, comparable link-budget to LongFast / ShortSlow.
			// Conservative middle-of-the-road SNR floor pending field data.
			return -12.5
		case .liteSlow:
			return -15
		case .narrowFast:
			// 62.5kHz narrow presets — similar to shortSlow link budget.
			return -10
		case .narrowSlow:
			return -12.5
		case .tinyFast:
			// 20kHz ham presets — narrowest bandwidth, best link budget.
			return -12.5
		case .tinySlow:
			return -15
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
		case .longTurbo:
			return Config.LoRaConfig.ModemPreset.longTurbo
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
		case .liteFast:
			return Config.LoRaConfig.ModemPreset.liteFast
		case .liteSlow:
			return Config.LoRaConfig.ModemPreset.liteSlow
		case .narrowFast:
			return Config.LoRaConfig.ModemPreset.narrowFast
		case .narrowSlow:
			return Config.LoRaConfig.ModemPreset.narrowSlow
		case .tinyFast:
			return Config.LoRaConfig.ModemPreset.tinyFast
		case .tinySlow:
			return Config.LoRaConfig.ModemPreset.tinySlow
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

///
/// Decoded, flattened view of a `LoRaRegionPresetMap` group for a single region:
/// the modem presets that are legal there, the firmware's default preset, and
/// whether the band is licensed-only (ham). Built from the grouped wire form per
/// the 2.8 "LoRa Region → Preset Compatibility" client spec.
struct RegionPresetInfo: Equatable {
	/// The modem presets the firmware considers legal for this region.
	let presets: Set<Config.LoRaConfig.ModemPreset>
	/// The firmware's default preset for this region; always a member of `presets`.
	/// Selected when the user switches to this region and the current preset is
	/// not legal there.
	let defaultPreset: Config.LoRaConfig.ModemPreset
	/// True for amateur/ham bands. The UI should warn/gate and coordinate with the
	/// operator's `is_licensed` flag.
	let licensedOnly: Bool
}

extension LoRaRegionPresetMap {
	/// Flatten the grouped wire form into a per-region lookup (spec §4). A region
	/// entry whose `group_index` is out of range is skipped defensively, which
	/// tolerates malformed or forward-compatible data. A region absent from the
	/// result carries no constraint and must not be restricted by the client.
	func decoded() -> [Config.LoRaConfig.RegionCode: RegionPresetInfo] {
		var result: [Config.LoRaConfig.RegionCode: RegionPresetInfo] = [:]
		for regionGroup in regionGroups {
			let index = Int(regionGroup.groupIndex)
			guard groups.indices.contains(index) else { continue }
			let group = groups[index]
			result[regionGroup.region] = RegionPresetInfo(
				presets: Set(group.presets),
				defaultPreset: group.defaultPreset,
				licensedOnly: group.licensedOnly
			)
		}
		return result
	}
}
