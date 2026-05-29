// EnumComprehensiveTests.swift
// MeshtasticTests

import Testing
import Foundation
import SwiftUI
import MapKit
@testable import Meshtastic

// MARK: - DeviceRoles Tests

@Suite("DeviceRoles Enum")
struct DeviceRolesEnumTests {

	@Test func allCases_count() {
		#expect(DeviceRoles.allCases.count == 11)
	}

	@Test func allCases_haveNames() {
		for role in DeviceRoles.allCases {
			#expect(!role.name.isEmpty, "Role \(role.rawValue) has empty name")
		}
	}

	@Test func allCases_haveDescriptions() {
		for role in DeviceRoles.allCases {
			#expect(!role.description.isEmpty, "Role \(role.rawValue) has empty description")
		}
	}

	@Test func allCases_haveSystemNames() {
		for role in DeviceRoles.allCases {
			#expect(!role.systemName.isEmpty, "Role \(role.rawValue) has empty systemName")
		}
	}

	@Test func allCases_haveProtoEnumValues() {
		for role in DeviceRoles.allCases {
			_ = role.protoEnumValue()
		}
	}

	@Test func identifiable_idMatchesRawValue() {
		for role in DeviceRoles.allCases {
			#expect(role.id == role.rawValue)
		}
	}

	@Test func client_isDefault() {
		#expect(DeviceRoles.client.rawValue == 0)
	}

	@Test func specificNames() {
		#expect(DeviceRoles.router.systemName == "wifi.router")
		#expect(DeviceRoles.tracker.systemName == "mappin.and.ellipse.circle")
		#expect(DeviceRoles.tak.systemName == "shield.checkered")
	}
}

// MARK: - RebroadcastModes Tests

@Suite("RebroadcastModes Enum")
struct RebroadcastModesEnumTests {

	@Test func allCases_count() {
		#expect(RebroadcastModes.allCases.count == 6)
	}

	@Test func allCases_haveNames() {
		for mode in RebroadcastModes.allCases {
			#expect(!mode.name.isEmpty)
		}
	}

	@Test func allCases_haveDescriptions() {
		for mode in RebroadcastModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func identifiable_idMatchesRawValue() {
		for mode in RebroadcastModes.allCases {
			#expect(mode.id == mode.rawValue)
		}
	}
}

// MARK: - Iaq Tests

@Suite("Iaq Enum")
struct IaqEnumTests {

	@Test func allCases_count() {
		#expect(Iaq.allCases.count == 7)
	}

	@Test func allCases_haveDescriptions() {
		for iaq in Iaq.allCases {
			#expect(!iaq.description.isEmpty)
		}
	}

	@Test func allCases_haveColors() {
		for iaq in Iaq.allCases {
			_ = iaq.color
		}
	}

	@Test func allCases_haveRanges() {
		for iaq in Iaq.allCases {
			let range = iaq.range
			#expect(!range.isEmpty)
		}
	}

	@Test func allCases_rangesDoNotOverlap() {
		let cases = Iaq.allCases.sorted { $0.range.lowerBound < $1.range.lowerBound }
		for i in 0..<(cases.count - 1) {
			#expect(cases[i].range.upperBound <= cases[i + 1].range.lowerBound,
				"Iaq ranges \(cases[i]) and \(cases[i + 1]) overlap")
		}
	}

	@Test func getIaq_excellent() {
		#expect(Iaq.getIaq(for: 25) == .excellent)
	}

	@Test func getIaq_good() {
		#expect(Iaq.getIaq(for: 75) == .good)
	}

	@Test func getIaq_lightlyPolluted() {
		#expect(Iaq.getIaq(for: 125) == .lightlyPolluted)
	}

	@Test func getIaq_moderatelyPolluted() {
		#expect(Iaq.getIaq(for: 175) == .moderatelyPolluted)
	}

	@Test func getIaq_heavilyPolluted() {
		#expect(Iaq.getIaq(for: 225) == .heavilyPolluted)
	}

	@Test func getIaq_severelyPolluted() {
		#expect(Iaq.getIaq(for: 300) == .severelyPolluted)
	}

	@Test func getIaq_extremelyPolluted() {
		#expect(Iaq.getIaq(for: 400) == .extremelyPolluted)
	}

	@Test func getIaq_boundaryValues() {
		#expect(Iaq.getIaq(for: 0) == .excellent)
		#expect(Iaq.getIaq(for: 50) == .excellent)
		#expect(Iaq.getIaq(for: 51) == .good)
		#expect(Iaq.getIaq(for: 100) == .good)
		#expect(Iaq.getIaq(for: 101) == .lightlyPolluted)
		#expect(Iaq.getIaq(for: 351) == .extremelyPolluted)
	}

	@Test func identifiable_idMatchesRawValue() {
		for iaq in Iaq.allCases {
			#expect(iaq.id == iaq.rawValue)
		}
	}
}

// MARK: - ScreenUnits Tests

@Suite("ScreenUnits Enum")
struct ScreenUnitsEnumTests {

	@Test func allCases() {
		#expect(ScreenUnits.allCases.count == 2)
	}

	@Test func descriptions() {
		#expect(ScreenUnits.metric.description == "Metric")
		#expect(ScreenUnits.imperial.description == "Imperial")
	}

	@Test func protoEnumValues() {
		_ = ScreenUnits.metric.protoEnumValue()
		_ = ScreenUnits.imperial.protoEnumValue()
	}

	@Test func identifiable() {
		#expect(ScreenUnits.metric.id == 0)
		#expect(ScreenUnits.imperial.id == 1)
	}
}

// MARK: - ScreenOnIntervals Tests

@Suite("ScreenOnIntervals Enum")
struct ScreenOnIntervalsEnumTests {

	@Test func allCases_haveDescriptions() {
		for interval in ScreenOnIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func allCases_identifiable() {
		for interval in ScreenOnIntervals.allCases {
			#expect(interval.id == interval.rawValue)
		}
	}

	@Test func max_isOneYear() {
		#expect(ScreenOnIntervals.max.rawValue == 31536000)
	}
}

// MARK: - ScreenCarouselIntervals Tests

@Suite("ScreenCarouselIntervals Enum")
struct ScreenCarouselIntervalsEnumTests {

	@Test func allCases_haveDescriptions() {
		for interval in ScreenCarouselIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func off_isZero() {
		#expect(ScreenCarouselIntervals.off.rawValue == 0)
	}
}

// MARK: - OledTypes Tests

@Suite("OledTypes Enum")
struct OledTypesEnumTests {

	@Test func allCases_haveDescriptions() {
		for type in OledTypes.allCases {
			#expect(!type.description.isEmpty)
		}
	}

	@Test func allCases_haveProtoValues() {
		for type in OledTypes.allCases {
			_ = type.protoEnumValue()
		}
	}

	@Test func auto_isDefault() {
		#expect(OledTypes.auto.rawValue == 0)
	}
}

// MARK: - DisplayModes Tests

@Suite("DisplayModes Enum")
struct DisplayModesEnumTests {

	@Test func allCases_haveDescriptions() {
		for mode in DisplayModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func defaultMode_isZero() {
		#expect(DisplayModes.defaultMode.rawValue == 0)
	}
}

// MARK: - MeshMapTypes Tests

@Suite("MeshMapTypes Enum")
struct MeshMapTypesEnumTests {

	@Test func allCases_haveDescriptions() {
		for type in MeshMapTypes.allCases {
			#expect(!type.description.isEmpty)
		}
	}

	@Test func allCases_haveMKMapTypes() {
		for type in MeshMapTypes.allCases {
			_ = type.MKMapTypeValue()
		}
	}

	@Test func identifiable() {
		for type in MeshMapTypes.allCases {
			#expect(type.id == type.rawValue)
		}
	}

	@Test func standard_isDefault() {
		#expect(MeshMapTypes.standard.rawValue == 0)
	}
}

// MARK: - MeshMapDistances Tests

@Suite("MeshMapDistances Enum")
struct MeshMapDistancesEnumTests {

	@Test func allCases_haveDescriptions() {
		for dist in MeshMapDistances.allCases {
			#expect(!dist.description.isEmpty)
		}
	}

	@Test func identifiable() {
		for dist in MeshMapDistances.allCases {
			#expect(dist.id == dist.rawValue)
		}
	}
}

// MARK: - UserTrackingModes Tests

@Suite("UserTrackingModes Enum")
struct UserTrackingModesEnumTests {

	@Test func allCases_haveDescriptions() {
		for mode in UserTrackingModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveIcons() {
		for mode in UserTrackingModes.allCases {
			#expect(!mode.icon.isEmpty)
		}
	}

	@Test func allCases_haveMKValues() {
		for mode in UserTrackingModes.allCases {
			_ = mode.MKUserTrackingModeValue()
		}
	}

	@Test func none_isDefault() {
		#expect(UserTrackingModes.none.rawValue == 0)
	}
}

// MARK: - RegionCodes Tests

@Suite("RegionCodes Enum")
struct RegionCodesEnumTests {

	@Test func allCases_haveTopics() {
		for region in RegionCodes.allCases {
			#expect(!region.topic.isEmpty)
		}
	}

	@Test func identifiable() {
		for region in RegionCodes.allCases {
			#expect(region.id == region.rawValue)
		}
	}

	@Test func us_topic() {
		#expect(RegionCodes.us.topic == "US")
	}

	@Test func eu868_topic() {
		#expect(RegionCodes.eu868.topic == "EU_868")
	}

	@Test func unset_isDefault() {
		#expect(RegionCodes.unset.rawValue == 0)
	}
}
