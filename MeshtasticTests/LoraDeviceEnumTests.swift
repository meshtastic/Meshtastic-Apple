import Foundation
import MapKit
import Testing

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
		#expect(RegionCodes.allCases.count == 25)
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
		#expect(ModemPresets.allCases.count == 9)
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
