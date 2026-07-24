import Foundation
import MapKit
import Testing
import MeshtasticProtobufs

@testable import Meshtastic

// MARK: - RegionCodes

@Suite("RegionCodes")
struct RegionCodesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for region in RegionCodes.allCases {
			#expect(!region.description.isEmpty, "RegionCodes.\(region) has empty description")
		}
	}

	@Test func allCases_haveNonEmptyTopic() {
		for region in RegionCodes.allCases {
			#expect(!region.topic.isEmpty, "RegionCodes.\(region) has empty topic")
		}
	}

	@Test func allCases_haveDutyCycle() {
		for region in RegionCodes.allCases {
			#expect(region.dutyCycle >= 0 && region.dutyCycle <= 100)
		}
	}

	@Test func allCases_haveIsCountryValue() {
		// Just exercise the property for all cases
		for region in RegionCodes.allCases {
			_ = region.isCountry
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for region in RegionCodes.allCases {
			_ = region.protoEnumValue()
		}
	}

	@Test func identifiable_idMatchesRawValue() {
		for region in RegionCodes.allCases {
			#expect(region.id == region.rawValue)
		}
	}

	@Test func totalCaseCount() {
		#expect(RegionCodes.allCases.count == 37)
	}

	@Test func eu433_hasDutyCycle10() {
		#expect(RegionCodes.eu433.dutyCycle == 10)
	}

	@Test func us_hasDutyCycle100() {
		#expect(RegionCodes.us.dutyCycle == 100)
	}

	@Test func unset_isNotCountry() {
		#expect(!RegionCodes.unset.isCountry)
	}

	@Test func us_isCountry() {
		#expect(RegionCodes.us.isCountry)
	}
}

// MARK: - ModemPresets

@Suite("ModemPresets")
struct ModemPresetsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for preset in ModemPresets.allCases {
			#expect(!preset.description.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyName() {
		for preset in ModemPresets.allCases {
			#expect(!preset.name.isEmpty)
		}
	}

	@Test func allCases_haveSnrLimit() {
		for preset in ModemPresets.allCases {
			let snr = preset.snrLimit()
			#expect(snr < 0, "SNR limit should be negative for \(preset)")
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for preset in ModemPresets.allCases {
			_ = preset.protoEnumValue()
		}
	}

	@Test func longFast_snrLimit() {
		#expect(ModemPresets.longFast.snrLimit() == -17.5)
	}

	@Test func shortTurbo_snrLimit() {
		#expect(ModemPresets.shortTurbo.snrLimit() == -7.5)
	}

	@Test func totalCaseCount() {
		#expect(ModemPresets.allCases.count == 16)
	}

	@Test func mediumTurbo_values() {
		#expect(ModemPresets.mediumTurbo.protoEnumValue() == .mediumTurbo)
		#expect(ModemPresets.mediumTurbo.snrLimit() == -12.5)
		#expect(ModemPresets.mediumTurbo.bandwidthMHz == 0.5)
	}
}

// MARK: - Bandwidths

@Suite("Bandwidths")
struct BandwidthsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for bw in Bandwidths.allCases {
			#expect(!bw.description.isEmpty)
		}
	}

	@Test func allCases_descriptionContainsKHz() {
		for bw in Bandwidths.allCases {
			#expect(bw.description.contains("kHz"))
		}
	}

	@Test func totalCaseCount() {
		#expect(Bandwidths.allCases.count == 5)
	}
}

// MARK: - DeviceRoles

@Suite("DeviceRoles")
struct DeviceRolesTests {

	@Test func allCases_haveNonEmptyName() {
		for role in DeviceRoles.allCases {
			#expect(!role.name.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyDescription() {
		for role in DeviceRoles.allCases {
			#expect(!role.description.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptySystemName() {
		for role in DeviceRoles.allCases {
			#expect(!role.systemName.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for role in DeviceRoles.allCases {
			_ = role.protoEnumValue()
		}
	}

	@Test func identifiable_idMatchesRawValue() {
		for role in DeviceRoles.allCases {
			#expect(role.id == role.rawValue)
		}
	}

	@Test func client_isDefaultZero() {
		#expect(DeviceRoles.client.rawValue == 0)
	}

	@Test func totalCaseCount() {
		#expect(DeviceRoles.allCases.count == 11)
	}
}

// MARK: - RebroadcastModes

@Suite("RebroadcastModes")
struct RebroadcastModesTests {

	@Test func allCases_haveNonEmptyName() {
		for mode in RebroadcastModes.allCases {
			#expect(!mode.name.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyDescription() {
		for mode in RebroadcastModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for mode in RebroadcastModes.allCases {
			_ = mode.protoEnumValue()
		}
	}

	@Test func totalCaseCount() {
		#expect(RebroadcastModes.allCases.count == 6)
	}
}

// MARK: - Display Enums

@Suite("ScreenUnits")
struct ScreenUnitsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for unit in ScreenUnits.allCases {
			#expect(!unit.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for unit in ScreenUnits.allCases {
			_ = unit.protoEnumValue()
		}
	}
}

@Suite("ScreenOnIntervals")
struct ScreenOnIntervalsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for interval in ScreenOnIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func max_isOneYear() {
		#expect(ScreenOnIntervals.max.rawValue == 31536000)
	}

	@Test func totalCaseCount() {
		#expect(ScreenOnIntervals.allCases.count == 9)
	}
}

@Suite("ScreenCarouselIntervals")
struct ScreenCarouselIntervalsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for interval in ScreenCarouselIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func off_isZero() {
		#expect(ScreenCarouselIntervals.off.rawValue == 0)
	}
}

@Suite("OledTypes")
struct OledTypesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for oled in OledTypes.allCases {
			#expect(!oled.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for oled in OledTypes.allCases {
			_ = oled.protoEnumValue()
		}
	}
}

@Suite("DisplayModes")
struct DisplayModesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for mode in DisplayModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for mode in DisplayModes.allCases {
			_ = mode.protoEnumValue()
		}
	}
}

@Suite("Units")
struct UnitsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for unit in Units.allCases {
			#expect(!unit.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for unit in Units.allCases {
			_ = unit.protoEnumValue()
		}
	}
}

// MARK: - Serial Config Enums

@Suite("SerialBaudRates")
struct SerialBaudRatesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for baud in SerialBaudRates.allCases {
			#expect(!baud.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for baud in SerialBaudRates.allCases {
			_ = baud.protoEnumValue()
		}
	}

	@Test func totalCaseCount() {
		#expect(SerialBaudRates.allCases.count == 16)
	}
}

@Suite("SerialModeTypes")
struct SerialModeTypesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for mode in SerialModeTypes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for mode in SerialModeTypes.allCases {
			_ = mode.protoEnumValue()
		}
	}
}

@Suite("SerialTimeoutIntervals")
struct SerialTimeoutIntervalsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for interval in SerialTimeoutIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(SerialTimeoutIntervals.allCases.count == 8)
	}
}

// MARK: - Position Config Enums

@Suite("GpsUpdateIntervals")
struct GpsUpdateIntervalsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for interval in GpsUpdateIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(GpsUpdateIntervals.allCases.count == 12)
	}

	@Test func maxInt32_isBootOnly() {
		#expect(GpsUpdateIntervals.maxInt32.rawValue == 2147483647)
	}
}

@Suite("GpsMode")
struct GpsModeTests {

	@Test func allCases_haveNonEmptyDescription() {
		for mode in GpsMode.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for mode in GpsMode.allCases {
			_ = mode.protoEnumValue()
		}
	}
}

// MARK: - Canned Messages Config

@Suite("ConfigPresets")
struct ConfigPresetsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for preset in ConfigPresets.allCases {
			#expect(!preset.description.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(ConfigPresets.allCases.count == 3)
	}
}

@Suite("InputEventChars")
struct InputEventCharsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for event in InputEventChars.allCases {
			#expect(!event.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for event in InputEventChars.allCases {
			_ = event.protoEnumValue()
		}
	}

	@Test func totalCaseCount() {
		#expect(InputEventChars.allCases.count == 8)
	}
}

// MARK: - Other Enums

@Suite("ChannelRoles")
struct ChannelRolesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for role in ChannelRoles.allCases {
			#expect(!role.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for role in ChannelRoles.allCases {
			_ = role.protoEnumValue()
		}
	}

	@Test func totalCaseCount() {
		#expect(ChannelRoles.allCases.count == 3)
	}
}

@Suite("BluetoothModes")
struct BluetoothModesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for mode in BluetoothModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for mode in BluetoothModes.allCases {
			_ = mode.protoEnumValue()
		}
	}

	@Test func totalCaseCount() {
		#expect(BluetoothModes.allCases.count == 3)
	}
}

@Suite("EthernetMode")
struct EthernetModeTests {

	@Test func allCases_haveNonEmptyDescription() {
		for mode in EthernetMode.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for mode in EthernetMode.allCases {
			_ = mode.protoEnumValue()
		}
	}
}

@Suite("KeyBackupStatus")
struct KeyBackupStatusTests {

	@Test func allCases_haveNonEmptyDescription() {
		for status in KeyBackupStatus.allCases {
			#expect(!status.description.isEmpty)
		}
	}

	@Test func successCases_returnTrue() {
		#expect(KeyBackupStatus.saved.success)
		#expect(KeyBackupStatus.restored.success)
		#expect(KeyBackupStatus.deleted.success)
	}

	@Test func failCases_returnFalse() {
		#expect(!KeyBackupStatus.saveFailed.success)
		#expect(!KeyBackupStatus.restoreFailed.success)
		#expect(!KeyBackupStatus.deleteFailed.success)
	}

	@Test func totalCaseCount() {
		#expect(KeyBackupStatus.allCases.count == 6)
	}
}

@Suite("WeatherConditions")
struct WeatherConditionsTests {

	@Test func allCases_haveNonEmptySymbolName() {
		for condition in WeatherConditions.allCases {
			#expect(!condition.symbolName.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(WeatherConditions.allCases.count == 7)
	}
}

@Suite("ActivityType")
struct ActivityTypeTests {

	@Test func allCases_haveNonEmptyDescription() {
		for activity in ActivityType.allCases {
			#expect(!activity.description.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyFileNameString() {
		for activity in ActivityType.allCases {
			#expect(!activity.fileNameString.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(ActivityType.allCases.count == 6)
	}
}

@Suite("TriggerTypes")
struct TriggerTypesTests {

	@Test func allCases_haveNonEmptyName() {
		for trigger in TriggerTypes.allCases {
			#expect(!trigger.name.isEmpty)
		}
	}

	@Test func allCases_haveProtoEnumValue() {
		for trigger in TriggerTypes.allCases {
			_ = trigger.protoEnumValue()
		}
	}

	@Test func totalCaseCount() {
		#expect(TriggerTypes.allCases.count == 6)
	}
}

// MARK: - Firmware gating (2.8 regions & presets)

@Suite("LoRa firmware gating")
struct LoRaFirmwareGatingTests {

	@Test func newRegions_requireFirmware2_8() {
		let newRegions: [RegionCodes] = [.eu866, .euN868, .itu12M, .itu22M, .itu32M, .itu170Cm, .itu270Cm, .itu370Cm, .itu2125Cm]
		for region in newRegions {
			#expect(region.requiresFirmware2_8, "\(region) should require 2.8")
		}
	}

	@Test func legacyRegions_doNotRequireFirmware2_8() {
		let legacy: [RegionCodes] = [.us, .eu433, .eu868, .anz, .lora24]
		for region in legacy {
			#expect(!region.requiresFirmware2_8, "\(region) should be available pre-2.8")
		}
	}

	@Test func oldFirmware_excludes2_8Regions() {
		let selectable = RegionCodes.selectable(supports2_8: false)
		#expect(!selectable.contains(.itu12M))
		#expect(!selectable.contains(.itu2125Cm))
		#expect(!selectable.contains(.eu866))
		#expect(!selectable.contains(.euN868))
		// Legacy regions remain available.
		#expect(selectable.contains(.us))
		#expect(selectable.contains(.eu868))
	}

	@Test func newFirmware_includes2_8Regions() {
		let selectable = RegionCodes.selectable(supports2_8: true)
		#expect(selectable.contains(.itu12M))
		#expect(selectable.contains(.itu2125Cm))
		#expect(selectable.contains(.eu866))
		#expect(selectable.contains(.euN868))
	}

	@Test func hiddenRegions_neverSelectable() {
		#expect(!RegionCodes.selectable(supports2_8: false).contains(.eu874))
		#expect(!RegionCodes.selectable(supports2_8: true).contains(.eu874))
		#expect(!RegionCodes.selectable(supports2_8: true).contains(.eu917))
	}

	@Test func userSelectable_matchesPre2_8() {
		#expect(RegionCodes.userSelectable == RegionCodes.selectable(supports2_8: false))
		#expect(ModemPresets.userSelectable == ModemPresets.selectable(supports2_8: false))
	}

	@Test func newPresets_requireFirmware2_8() {
		let newPresets: [ModemPresets] = [.liteFast, .liteSlow, .narrowFast, .narrowSlow, .tinyFast, .tinySlow]
		for preset in newPresets {
			#expect(preset.requiresFirmware2_8, "\(preset) should require 2.8")
		}
	}

	@Test func oldFirmware_excludes2_8Presets() {
		let selectable = ModemPresets.selectable(supports2_8: false)
		#expect(!selectable.contains(.narrowFast))
		#expect(!selectable.contains(.tinyFast))
		#expect(!selectable.contains(.liteSlow))
		#expect(selectable.contains(.longFast))
		#expect(selectable.contains(.shortTurbo))
	}

	@Test func newFirmware_includes2_8Presets() {
		let selectable = ModemPresets.selectable(supports2_8: true)
		#expect(selectable.contains(.narrowFast))
		#expect(selectable.contains(.tinyFast))
		#expect(selectable.contains(.liteSlow))
	}

	@Test func deprecatedPreset_excludedFromSelectable() {
		#expect(ModemPresets.longSlow.isDeprecated)
		#expect(!ModemPresets.selectable(supports2_8: false).contains(.longSlow))
		#expect(!ModemPresets.selectable(supports2_8: true).contains(.longSlow))
		#expect(!ModemPresets.userSelectable.contains(.longSlow))
	}

	@Test func deprecatedPreset_stillExistsForDisplay() {
		// longSlow remains a case so an existing radio's value round-trips and renders its label.
		let preset = ModemPresets(rawValue: 1)
		#expect(preset == .longSlow)
		#expect(preset?.name == "LongSlow")
	}
}

// MARK: - LoRaRegionPresetMap decoding (2.8 region→preset compatibility)

@Suite("LoRaRegionPresetMap decoding")
struct LoRaRegionPresetMapTests {

	typealias Preset = Config.LoRaConfig.ModemPreset
	typealias Region = Config.LoRaConfig.RegionCode

	/// Builds the reference 2.8 firmware table from the client spec §9 (6 groups).
	private func referenceMap() -> LoRaRegionPresetMap {
		func group(_ presets: [Preset], _ def: Preset, _ licensed: Bool) -> LoRaPresetGroup {
			var g = LoRaPresetGroup()
			g.presets = presets
			g.defaultPreset = def
			g.licensedOnly = licensed
			return g
		}
		func entry(_ region: Region, _ index: UInt32) -> LoRaRegionPresets {
			var e = LoRaRegionPresets()
			e.region = region
			e.groupIndex = index
			return e
		}

		var map = LoRaRegionPresetMap()
		map.groups = [
			group([.longFast, .longSlow, .mediumSlow, .mediumFast, .shortSlow, .shortFast, .longModerate, .shortTurbo, .longTurbo], .longFast, false),
			group([.longFast, .longSlow, .mediumSlow, .mediumFast, .shortSlow, .shortFast, .longModerate], .longFast, false),
			group([.liteFast, .liteSlow], .liteFast, false),
			group([.narrowFast, .narrowSlow], .narrowSlow, false),
			group([.tinyFast, .tinySlow], .tinyFast, true),
			group([.narrowFast, .narrowSlow], .narrowSlow, true)
		]
		let group0Regions: [Region] = [.us, .eu433, .cn, .jp, .anz, .anz433, .ru, .kr, .tw, .in, .nz865, .th, .ua433, .my433, .my919, .sg923, .ph433, .ph868, .ph915, .kz433, .kz863, .np865, .br902, .lora24]
		map.regionGroups = group0Regions.map { entry($0, 0) }
		map.regionGroups.append(entry(.eu868, 1))
		map.regionGroups.append(entry(.eu866, 2))
		map.regionGroups.append(entry(.euN868, 3))
		map.regionGroups.append(contentsOf: [entry(.itu12M, 4), entry(.itu22M, 4), entry(.itu32M, 4)])
		map.regionGroups.append(entry(.itu2125Cm, 5))
		return map
	}

	@Test func decode_standardRegion() {
		let info = referenceMap().decoded()[.us]
		#expect(info != nil)
		#expect(info?.presets.count == 9)
		#expect(info?.defaultPreset == .longFast)
		#expect(info?.licensedOnly == false)
		#expect(info?.presets.contains(.longFast) == true)
		#expect(info?.presets.contains(.narrowFast) == false)
	}

	@Test func decode_eu868() {
		let info = referenceMap().decoded()[.eu868]
		#expect(info?.presets.count == 7)
		#expect(info?.defaultPreset == .longFast)
		#expect(info?.presets.contains(.shortTurbo) == false)
	}

	@Test func decode_eu866Lite() {
		let info = referenceMap().decoded()[.eu866]
		#expect(info?.presets == Set<Preset>([.liteFast, .liteSlow]))
		#expect(info?.defaultPreset == .liteFast)
		#expect(info?.licensedOnly == false)
	}

	@Test func decode_euNarrow() {
		let info = referenceMap().decoded()[.euN868]
		#expect(info?.presets == Set<Preset>([.narrowFast, .narrowSlow]))
		#expect(info?.defaultPreset == .narrowSlow)
		#expect(info?.licensedOnly == false)
	}

	@Test func decode_ham2mIsLicensed() {
		let info = referenceMap().decoded()[.itu12M]
		#expect(info?.presets == Set<Preset>([.tinyFast, .tinySlow]))
		#expect(info?.defaultPreset == .tinyFast)
		#expect(info?.licensedOnly == true)
	}

	/// Groups 3 and 5 share the same preset list but differ in licensing; the
	/// decoder must key on the group and preserve the per-group flag (spec §9).
	@Test func decode_ham125cmSharesPresetsButLicensed() {
		let map = referenceMap().decoded()
		#expect(map[.itu2125Cm]?.presets == Set<Preset>([.narrowFast, .narrowSlow]))
		#expect(map[.itu2125Cm]?.licensedOnly == true)
		#expect(map[.euN868]?.licensedOnly == false)
	}

	@Test func decode_allRegionsPresent() {
		#expect(referenceMap().decoded().count == 31)
	}

	@Test func absentRegion_hasNoConstraint() {
		// EU_874 / EU_917 have no firmware band table entry (spec §5.1).
		let map = referenceMap().decoded()
		#expect(map[.eu874] == nil)
		#expect(map[.eu917] == nil)
	}

	@Test func outOfRangeGroupIndex_isSkipped() {
		var map = referenceMap()
		var bad = LoRaRegionPresets()
		bad.region = .eu874
		bad.groupIndex = 99   // out of range — forward / malformed data
		map.regionGroups.append(bad)
		let decoded = map.decoded()
		#expect(decoded[.eu874] == nil)   // skipped defensively (spec §4)
		#expect(decoded.count == 31)      // unchanged
	}

	@Test func emptyMap_decodesEmpty() {
		#expect(LoRaRegionPresetMap().decoded().isEmpty)
	}

	// veryLongSlow (proto rawValue 2) is intentionally absent from the UI
	// `ModemPresets` enum. A region whose advertised `default_preset` mapped to a
	// missing case would have no picker entry, so the LoRa view guards against
	// selecting it (the Save path force-unwraps `ModemPresets(rawValue:)`).
	@Test func unmappedDefaultPreset_hasNoUICase() {
		#expect(ModemPresets(rawValue: Preset.veryLongSlow.rawValue) == nil)
	}
}

// MARK: - Region-change preset selection (factory default + fallback)

@Suite("LoRa preset selection")
struct LoRaPresetSelectionTests {
	typealias Preset = Config.LoRaConfig.ModemPreset

	private let usInfo = RegionPresetInfo(
		presets: Set<Preset>([.longFast, .longSlow, .mediumSlow, .mediumFast, .shortSlow, .shortFast, .longModerate, .shortTurbo, .longTurbo]),
		defaultPreset: .longFast,
		licensedOnly: false)

	private let euNarrowInfo = RegionPresetInfo(
		presets: Set<Preset>([.narrowFast, .narrowSlow]),
		defaultPreset: .narrowSlow,
		licensedOnly: false)

	// A factory-flashed (region unset) node on 2.8 firmware defaults to Long Turbo
	// when the US region is selected.
	@Test func factoryUS_on28_defaultsToLongTurbo() {
		let result = ModemPresets.presetToSelect(forRegion: .us, factoryFresh: true, supports2_8: true, usePreset: true, regionInfo: usInfo, currentPreset: .longFast)
		#expect(result == .longTurbo)
	}

	// US allows Long Turbo even before the region map has been received.
	@Test func factoryUS_withoutMap_stillDefaultsToLongTurbo() {
		let result = ModemPresets.presetToSelect(forRegion: .us, factoryFresh: true, supports2_8: true, usePreset: true, regionInfo: nil, currentPreset: .longFast)
		#expect(result == .longTurbo)
	}

	// An already-configured US node keeps its (legal) preset.
	@Test func configuredUS_keepsLegalPreset() {
		let result = ModemPresets.presetToSelect(forRegion: .us, factoryFresh: false, supports2_8: true, usePreset: true, regionInfo: usInfo, currentPreset: .longFast)
		#expect(result == nil)
	}

	// The Long Turbo default is 2.8-only.
	@Test func factoryUS_onOldFirmware_noOverride() {
		let result = ModemPresets.presetToSelect(forRegion: .us, factoryFresh: true, supports2_8: false, usePreset: true, regionInfo: nil, currentPreset: .longFast)
		#expect(result == nil)
	}

	// The factory Long Turbo default applies only to US; other regions fall back to
	// their advertised default when the current preset is illegal there.
	@Test func factoryNonUS_doesNotForceLongTurbo() {
		let result = ModemPresets.presetToSelect(forRegion: .euN868, factoryFresh: true, supports2_8: true, usePreset: true, regionInfo: euNarrowInfo, currentPreset: .longFast)
		#expect(result == .narrowSlow)
	}

	@Test func illegalPreset_fallsBackToRegionDefault() {
		let result = ModemPresets.presetToSelect(forRegion: .euN868, factoryFresh: false, supports2_8: true, usePreset: true, regionInfo: euNarrowInfo, currentPreset: .longFast)
		#expect(result == .narrowSlow)
	}

	@Test func legalPreset_isKept() {
		let result = ModemPresets.presetToSelect(forRegion: .euN868, factoryFresh: false, supports2_8: true, usePreset: true, regionInfo: euNarrowInfo, currentPreset: .narrowFast)
		#expect(result == nil)
	}

	@Test func usePresetOff_noChange() {
		let result = ModemPresets.presetToSelect(forRegion: .us, factoryFresh: true, supports2_8: true, usePreset: false, regionInfo: usInfo, currentPreset: .longFast)
		#expect(result == nil)
	}

	// Defensive: if the US map somehow lacks Long Turbo, don't force it — keep the
	// legal current preset.
	@Test func factoryUS_longTurboIllegal_keepsLegalCurrent() {
		let usNoTurbo = RegionPresetInfo(presets: Set<Preset>([.longFast, .longSlow]), defaultPreset: .longFast, licensedOnly: false)
		let result = ModemPresets.presetToSelect(forRegion: .us, factoryFresh: true, supports2_8: true, usePreset: true, regionInfo: usNoTurbo, currentPreset: .longFast)
		#expect(result == nil)
	}
}

@Suite("LoRa channel frequency calculation")
struct LoRaChannelCalculatorTests {
	@Test("ITU Region 2 TinyFast defaults to firmware slot 51 at 145.010 MHz")
	func itu2TinyFastDefault() {
		let calculator = LoRaChannelCalculator(
			regionCode: RegionCodes.itu22M.rawValue,
			usePreset: true,
			modemPreset: ModemPresets.tinyFast.rawValue,
			channelNum: 0,
			bandwidth: 0,
			overrideFrequency: 0
		)

		let slot = calculator.effectiveChannelSlot(primaryName: "TinyFast")
		#expect(slot == 51)
		#expect(abs(calculator.radioFrequencyMHz(slot: slot) - 145.010) < 0.001)
	}

	@Test("ITU Region 2 TinyFast explicit slots advance by 20 kHz")
	func itu2TinyFastExplicitSlot() {
		let calculator = LoRaChannelCalculator(
			regionCode: RegionCodes.itu22M.rawValue,
			usePreset: true,
			modemPreset: ModemPresets.tinyFast.rawValue,
			channelNum: 52,
			bandwidth: 0,
			overrideFrequency: 0
		)

		let slot = calculator.effectiveChannelSlot(primaryName: "TinyFast")
		#expect(slot == 52)
		#expect(abs(calculator.radioFrequencyMHz(slot: slot) - 145.030) < 0.001)
	}

	@Test("EU_866 LiteFast uses the firmware Lite band plan")
	func eu866LiteFast() {
		let calculator = LoRaChannelCalculator(
			regionCode: RegionCodes.eu866.rawValue,
			usePreset: true,
			modemPreset: ModemPresets.liteFast.rawValue,
			channelNum: 0,
			bandwidth: 0,
			overrideFrequency: 0
		)

		// Firmware PROFILE_LITE: 400 kHz spacing + 37.5 kHz padding on either side
		// of LiteFast's 125 kHz bandwidth → four 600 kHz slots in 865.6–867.6 MHz.
		#expect(abs(calculator.radioFrequencyMHz(slot: 1) - 865.700) < 0.001)
		#expect(abs(calculator.radioFrequencyMHz(slot: 4) - 867.500) < 0.001)
	}

	@Test("Channel frequency applies the configured offset after the firmware slot calculation")
	func appliesFrequencyOffset() {
		let calculator = LoRaChannelCalculator(
			regionCode: RegionCodes.itu22M.rawValue,
			usePreset: true,
			modemPreset: ModemPresets.tinyFast.rawValue,
			channelNum: 0,
			bandwidth: 0,
			overrideFrequency: 0,
			frequencyOffset: 0.010
		)

		let slot = calculator.effectiveChannelSlot(primaryName: "TinyFast")
		#expect(abs(calculator.radioFrequencyMHz(slot: slot) - 145.020) < 0.001)
	}

	@Test("Override frequency applies the configured offset regardless of slot")
	func overrideFrequencyAppliesOffset() {
		let calculator = LoRaChannelCalculator(
			regionCode: RegionCodes.itu22M.rawValue,
			usePreset: true,
			modemPreset: ModemPresets.tinyFast.rawValue,
			channelNum: 0,
			bandwidth: 0,
			overrideFrequency: 145.500,
			frequencyOffset: 0.010
		)

		#expect(abs(calculator.radioFrequencyMHz(slot: 999) - 145.510) < 0.001)
	}

	@Test("ITU Region 2 1.25m uses the 100 kHz ham channel plan")
	func itu2OnePointTwoFiveMeterDefault() {
		let calculator = LoRaChannelCalculator(
			regionCode: RegionCodes.itu2125Cm.rawValue,
			usePreset: true,
			modemPreset: ModemPresets.narrowSlow.rawValue,
			channelNum: 0,
			bandwidth: 0,
			overrideFrequency: 0
		)

		let slot = calculator.effectiveChannelSlot(primaryName: "NarrowSlow")
		#expect(slot == 37)
		#expect(abs(calculator.radioFrequencyMHz(slot: slot) - 223.650) < 0.001)
	}

	@Test("US LongFast keeps standard channel centers")
	func usLongFast() {
		let calculator = LoRaChannelCalculator(
			regionCode: RegionCodes.us.rawValue,
			usePreset: true,
			modemPreset: ModemPresets.longFast.rawValue,
			channelNum: 1,
			bandwidth: 0,
			overrideFrequency: 0
		)

		#expect(abs(calculator.radioFrequencyMHz(slot: 1) - 902.125) < 0.001)
	}
}
