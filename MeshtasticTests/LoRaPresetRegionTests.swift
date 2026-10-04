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
	// not offered there at all. All six EU regions, including the narrow-band ones the
	// 2.8 rework added; euN868's legal group is narrow fast and narrow slow only.
	@Test(arguments: [RegionCodes.eu433, .eu868, .eu866, .eu874, .eu917, .euN868])
	func euRegionsProhibitTurbo(_ region: RegionCodes) {
		#expect(region.prohibitsTurboPresets)
	}

	// The rule that keeps a picker from rendering blank. It used to re-add only a
	// deprecated preset, so an EU radio already set to Turbo had no matching option at
	// all: it could not see what its own radio was on.
	@Test("Whatever the radio is set to stays in the list")
	func configuredPresetSurvivesFiltering() {
		let euOffered = ModemPresets.allCases.filter { !$0.isTurbo }
		for configured in [ModemPresets.longTurbo, .shortTurbo, .mediumTurbo, .longSlow] {
			var presets = euOffered
            if !presets.contains(configured) { presets.append(configured) }
			#expect(presets.contains(configured),
					"\(configured) is what the radio reports; hiding it leaves a blank picker")
		}
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
