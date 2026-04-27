// EnumBatchTests.swift
// MeshtasticTests

import Testing
import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

// MARK: - SerialBaudRates Tests

@Suite("SerialBaudRates Enum")
struct SerialBaudRatesEnumTests {

	@Test func allCases_count() {
		#expect(SerialBaudRates.allCases.count == 16)
	}

	@Test func allCases_haveDescriptions() {
		for rate in SerialBaudRates.allCases {
			#expect(!rate.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoValues() {
		for rate in SerialBaudRates.allCases {
			_ = rate.protoEnumValue()
		}
	}

	@Test func identifiable() {
		for rate in SerialBaudRates.allCases {
			#expect(rate.id == rate.rawValue)
		}
	}
}

// MARK: - SerialModeTypes Tests

@Suite("SerialModeTypes Enum")
struct SerialModeTypesEnumTests {

	@Test func allCases_count() {
		#expect(SerialModeTypes.allCases.count == 6)
	}

	@Test func allCases_haveDescriptions() {
		for mode in SerialModeTypes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoValues() {
		for mode in SerialModeTypes.allCases {
			_ = mode.protoEnumValue()
		}
	}
}

// MARK: - SerialTimeoutIntervals Tests

@Suite("SerialTimeoutIntervals Enum")
struct SerialTimeoutIntervalsEnumTests {

	@Test func allCases_count() {
		#expect(SerialTimeoutIntervals.allCases.count == 8)
	}

	@Test func allCases_haveDescriptions() {
		for interval in SerialTimeoutIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}
}

// MARK: - GpsUpdateIntervals Tests

@Suite("GpsUpdateIntervals Enum")
struct GpsUpdateIntervalsEnumTests {

	@Test func allCases_count() {
		#expect(GpsUpdateIntervals.allCases.count == 12)
	}

	@Test func allCases_haveDescriptions() {
		for interval in GpsUpdateIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func identifiable() {
		for interval in GpsUpdateIntervals.allCases {
			#expect(interval.id == interval.rawValue)
		}
	}

	@Test func maxInt32_isOnBoot() {
		#expect(GpsUpdateIntervals.maxInt32.rawValue == 2147483647)
	}
}

// MARK: - GpsMode Tests

@Suite("GpsMode Enum")
struct GpsModeEnumTests {

	@Test func allCases_count() {
		#expect(GpsMode.allCases.count == 3)
	}

	@Test func allCases_haveDescriptions() {
		for mode in GpsMode.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoValues() {
		for mode in GpsMode.allCases {
			_ = mode.protoEnumValue()
		}
	}

	@Test func equatable() {
		#expect(GpsMode.enabled == GpsMode.enabled)
		#expect(GpsMode.enabled != GpsMode.disabled)
	}
}

// MARK: - ConfigPresets Tests

@Suite("ConfigPresets Enum")
struct ConfigPresetsEnumTests {

	@Test func allCases_count() {
		#expect(ConfigPresets.allCases.count == 3)
	}

	@Test func allCases_haveDescriptions() {
		for preset in ConfigPresets.allCases {
			#expect(!preset.description.isEmpty)
		}
	}

	@Test func identifiable() {
		for preset in ConfigPresets.allCases {
			#expect(preset.id == preset.rawValue)
		}
	}
}

// MARK: - InputEventChars Tests

@Suite("InputEventChars Enum")
struct InputEventCharsEnumTests {

	@Test func allCases_count() {
		#expect(InputEventChars.allCases.count == 8)
	}

	@Test func allCases_haveDescriptions() {
		for char in InputEventChars.allCases {
			#expect(!char.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoValues() {
		for char in InputEventChars.allCases {
			_ = char.protoEnumValue()
		}
	}

	@Test func specificValues() {
		#expect(InputEventChars.up.rawValue == 17)
		#expect(InputEventChars.down.rawValue == 18)
		#expect(InputEventChars.select.rawValue == 10)
		#expect(InputEventChars.back.rawValue == 27)
	}
}

// MARK: - Tapbacks Tests

@Suite("Tapbacks Enum")
struct TapbacksEnumTests {

	@Test func allCases_count() {
		#expect(Tapbacks.allCases.count == 8)
	}

	@Test func allCases_haveEmojiStrings() {
		for tapback in Tapbacks.allCases {
			#expect(!tapback.emojiString.isEmpty)
		}
	}

	@Test func allCases_haveDescriptions() {
		for tapback in Tapbacks.allCases {
			#expect(!tapback.description.isEmpty)
		}
	}

	@Test func specificEmoji() {
		#expect(Tapbacks.wave.emojiString == "👋")
		#expect(Tapbacks.heart.emojiString == "❤️")
		#expect(Tapbacks.thumbsUp.emojiString == "👍")
		#expect(Tapbacks.thumbsDown.emojiString == "👎")
		#expect(Tapbacks.haHa.emojiString == "🤣")
		#expect(Tapbacks.poop.emojiString == "💩")
	}

	@Test func identifiable() {
		for tapback in Tapbacks.allCases {
			#expect(tapback.id == tapback.rawValue)
		}
	}
}

// MARK: - ActivityType Tests

@Suite("ActivityType Enum")
struct ActivityTypeEnumTests {

	@Test func allCases_count() {
		#expect(ActivityType.allCases.count == 6)
	}

	@Test func allCases_haveDescriptions() {
		for type in ActivityType.allCases {
			#expect(!type.description.isEmpty)
		}
	}

	@Test func allCases_haveFileNameStrings() {
		for type in ActivityType.allCases {
			#expect(!type.fileNameString.isEmpty)
		}
	}

	@Test func fileNameString_isLowercase() {
		for type in ActivityType.allCases {
			#expect(type.fileNameString == type.fileNameString.lowercased())
		}
	}
}

// MARK: - TriggerTypes Tests

@Suite("TriggerTypes Enum")
struct TriggerTypesEnumTests {

	@Test func allCases_count() {
		#expect(TriggerTypes.allCases.count == 6)
	}

	@Test func allCases_haveNames() {
		for type in TriggerTypes.allCases {
			#expect(!type.name.isEmpty)
		}
	}

	@Test func allCases_haveProtoValues() {
		for type in TriggerTypes.allCases {
			_ = type.protoEnumValue()
		}
	}
}

// MARK: - KeyBackupStatus Tests

@Suite("KeyBackupStatus Enum")
struct KeyBackupStatusEnumTests {

	@Test func allCases_count() {
		#expect(KeyBackupStatus.allCases.count == 6)
	}

	@Test func allCases_haveDescriptions() {
		for status in KeyBackupStatus.allCases {
			#expect(!status.description.isEmpty)
		}
	}

	@Test func successStates() {
		#expect(KeyBackupStatus.saved.success == true)
		#expect(KeyBackupStatus.restored.success == true)
		#expect(KeyBackupStatus.deleted.success == true)
	}

	@Test func failureStates() {
		#expect(KeyBackupStatus.saveFailed.success == false)
		#expect(KeyBackupStatus.restoreFailed.success == false)
		#expect(KeyBackupStatus.deleteFailed.success == false)
	}

	@Test func decodable() throws {
		let json = "\"saved\""
		let data = json.data(using: .utf8)!
		let decoded = try JSONDecoder().decode(KeyBackupStatus.self, from: data)
		#expect(decoded == .saved)
	}

	@Test func equatable() {
		#expect(KeyBackupStatus.saved == KeyBackupStatus.saved)
		#expect(KeyBackupStatus.saved != KeyBackupStatus.deleted)
	}
}

// MARK: - WeatherConditions Tests

@Suite("WeatherConditions Enum")
struct WeatherConditionsEnumTests {

	@Test func allCases_count() {
		#expect(WeatherConditions.allCases.count == 7)
	}

	@Test func allCases_haveSymbolNames() {
		for condition in WeatherConditions.allCases {
			#expect(!condition.symbolName.isEmpty)
		}
	}

	@Test func specificSymbols() {
		#expect(WeatherConditions.clear.symbolName == "sparkle")
		#expect(WeatherConditions.cloudy.symbolName == "cloud")
		#expect(WeatherConditions.rain.symbolName == "cloud.rain")
		#expect(WeatherConditions.snow.symbolName == "cloud.snow")
		#expect(WeatherConditions.smoky.symbolName == "smoke")
	}

	@Test func identifiable() {
		for condition in WeatherConditions.allCases {
			#expect(condition.id == condition.rawValue)
		}
	}
}

// MARK: - BluetoothModes Tests

@Suite("BluetoothModes Enum")
struct BluetoothModesEnumTests {

	@Test func allCases_count() {
		#expect(BluetoothModes.allCases.count == 3)
	}

	@Test func allCases_haveDescriptions() {
		for mode in BluetoothModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoValues() {
		for mode in BluetoothModes.allCases {
			_ = mode.protoEnumValue()
		}
	}

	@Test func identifiable() {
		for mode in BluetoothModes.allCases {
			#expect(mode.id == mode.rawValue)
		}
	}
}

// MARK: - ChannelRoles Tests

@Suite("ChannelRoles Enum")
struct ChannelRolesEnumTests {

	@Test func allCases_count() {
		#expect(ChannelRoles.allCases.count == 3)
	}

	@Test func allCases_haveDescriptions() {
		for role in ChannelRoles.allCases {
			#expect(!role.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoValues() {
		for role in ChannelRoles.allCases {
			_ = role.protoEnumValue()
		}
	}

	@Test func specificValues() {
		#expect(ChannelRoles.disabled.rawValue == 0)
		#expect(ChannelRoles.primary.rawValue == 1)
		#expect(ChannelRoles.secondary.rawValue == 2)
	}
}

// MARK: - Units Tests (from DisplayEnums)

@Suite("Units Enum")
struct UnitsEnumTests {

	@Test func allCases_count() {
		#expect(Units.allCases.count == 2)
	}

	@Test func descriptions() {
		#expect(Units.metric.description == "Metric")
		#expect(Units.imperial.description == "Imperial")
	}

	@Test func protoEnumValues() {
		_ = Units.metric.protoEnumValue()
		_ = Units.imperial.protoEnumValue()
	}
}
