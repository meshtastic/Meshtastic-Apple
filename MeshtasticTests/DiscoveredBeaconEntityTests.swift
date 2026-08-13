// MARK: DiscoveredBeaconEntityTests

import Testing
import Foundation
@testable import Meshtastic

/// Locks down the sentinel semantics of DiscoveredBeaconEntity's advertised preset/region mapping.
/// The tricky part: offerPreset uses -1 (not 0) for "not offered" because 0 is a valid preset
/// (LongFast), while offerRegion uses 0 for "unset" (matching RegionCodes.unset == 0).
@Suite("DiscoveredBeaconEntity")
@MainActor
struct DiscoveredBeaconEntityTests {

	// MARK: offeredPreset

	@Test func offerPresetSentinelMeansNoPreset() {
		let beacon = DiscoveredBeaconEntity()
		beacon.offerPreset = -1
		#expect(beacon.offeredPreset == nil)
	}

	@Test func offerPresetZeroIsLongFastNotNil() {
		let beacon = DiscoveredBeaconEntity()
		beacon.offerPreset = 0
		#expect(beacon.offeredPreset == .longFast)
	}

	@Test func offerPresetMapsByRawValue() {
		let beacon = DiscoveredBeaconEntity()
		beacon.offerPreset = ModemPresets.shortFast.rawValue
		#expect(beacon.offeredPreset == .shortFast)
	}

	// MARK: offeredRegion

	@Test func offerRegionZeroMeansUnset() {
		let beacon = DiscoveredBeaconEntity()
		beacon.offerRegion = 0
		#expect(beacon.offeredRegion == nil)
	}

	@Test func offerRegionMapsByRawValue() {
		let beacon = DiscoveredBeaconEntity()
		beacon.offerRegion = RegionCodes.us.rawValue
		#expect(beacon.offeredRegion == .us)
	}

	// MARK: displayName

	@Test func displayNamePrefersLongName() {
		let beacon = DiscoveredBeaconEntity()
		beacon.longName = "Base Camp"
		beacon.shortName = "BC"
		#expect(beacon.displayName == "Base Camp")
	}

	@Test func displayNameFallsBackToShortName() {
		let beacon = DiscoveredBeaconEntity()
		beacon.shortName = "BC"
		#expect(beacon.displayName == "BC")
	}

	@Test func displayNameFallsBackToHexId() {
		let beacon = DiscoveredBeaconEntity()
		beacon.nodeNum = 0x12345678
		#expect(beacon.displayName == "!12345678")
	}
}
