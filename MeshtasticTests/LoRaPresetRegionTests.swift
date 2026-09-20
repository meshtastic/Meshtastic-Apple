//
//  LoRaPresetRegionTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import Testing
@testable import Meshtastic

/// Which presets a region allows is a regulatory question, not a presentation one, so
/// it is pinned here rather than left to a reading of the picker.
@Suite("LoRa presets by region")
struct LoRaPresetRegionTests {

	@Test("Only the three Turbo presets count as Turbo")
	func turboPresets() {
		let turbo = ModemPresets.allCases.filter(\.isTurbo)
		#expect(Set(turbo) == Set([.longTurbo, .shortTurbo, .mediumTurbo]))
	}

	// The EU band plans cap channel bandwidth below what Turbo uses, so those presets are
	// not offered there at all. All five EU regions, including the narrow-band ones the
	// 2.8 rework added.
	@Test(arguments: [RegionCodes.eu433, .eu868, .eu866, .eu874, .eu917])
	func euRegionsProhibitTurbo(_ region: RegionCodes) {
		#expect(region.prohibitsTurboPresets)
	}

	@Test("Other regions allow Turbo")
	func otherRegionsAllowTurbo() {
		#expect(!RegionCodes.us.prohibitsTurboPresets)
		#expect(!RegionCodes.anz.prohibitsTurboPresets)
		// A region the app does not recognise must not silently forbid anything.
		#expect(!RegionCodes.unset.prohibitsTurboPresets)
	}

	// In the US the non-Turbo presets stay selectable but are flagged: their bandwidth is
	// not compliant there on 2.8 firmware. Turbo is what the band plan expects.
	@Test("Every non-Turbo preset is the one warned about in the US")
	func usWarnsEveryNonTurboPreset() {
		let warned = ModemPresets.allCases.filter { !$0.isTurbo }
		#expect(warned.contains(.longFast), "the preset that used to be the only one warned about")
		#expect(warned.contains(.medFast))
		#expect(warned.contains(.shortSlow))
		#expect(!warned.contains(.longTurbo))
		#expect(warned.count == ModemPresets.allCases.count - 3)
	}
}
