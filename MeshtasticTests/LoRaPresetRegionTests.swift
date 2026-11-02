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
		for configured in [ModemPresets.longTurbo, .shortTurbo, .mediumTurbo, .longSlow] {
			let presets = ModemPresets.available(forRegion: .eu868, current: configured, supports2_8: true, regionInfo: nil)
			#expect(presets.last == configured,
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
		let warned = ModemPresets.allCases.filter {
			ModemPresets.usBandwidthWarning(region: .us, preset: $0, supports2_8: true) != nil
		}
		#expect(warned.contains(.longFast), "the preset that used to be the only one warned about")
		#expect(warned.contains(.medFast))
		#expect(warned.contains(.shortSlow))
		#expect(!warned.contains(.longTurbo))
		#expect(warned.count == ModemPresets.allCases.count - 3)
	}

	@Test func bandLimitedPresetsBelongOnlyToTheirRegions() {
		#expect(!RegionCodes.us.allowsBandLimitedPresets)
		#expect(!RegionCodes.anz.allowsBandLimitedPresets)
		#expect(RegionCodes.euN868.allowsBandLimitedPresets)
		#expect(RegionCodes.itu22M.allowsBandLimitedPresets)
		let bandLimited = ModemPresets.allCases.filter(\.isBandLimited)
		#expect(Set(bandLimited) == [.liteFast, .liteSlow, .narrowFast, .narrowSlow, .tinyFast, .tinySlow])
	}

	@Test("The warning names the preset and only applies to the US on 2.8")
	func usWarningScope() {
		let warning = ModemPresets.usBandwidthWarning(region: .us, preset: .longFast, supports2_8: true)
		#expect(warning?.contains(ModemPresets.longFast.description) == true)
		#expect(ModemPresets.usBandwidthWarning(region: .us, preset: .longTurbo, supports2_8: true) == nil)
		#expect(ModemPresets.usBandwidthWarning(region: .eu868, preset: .longFast, supports2_8: true) == nil)
		#expect(ModemPresets.usBandwidthWarning(region: .us, preset: .longFast, supports2_8: false) == nil)
		#expect(ModemPresets.usBandwidthWarning(region: nil, preset: .longFast, supports2_8: true) == nil)
	}

	// MARK: - The list a picker offers

	@Test("Without a map, the EU keeps its band-limited presets and loses Turbo")
	func euWithoutMap() {
		let presets = ModemPresets.available(forRegion: .eu868, current: nil, supports2_8: true, regionInfo: nil)
		#expect(!presets.contains(.longTurbo))
		#expect(presets.contains(.liteFast))
		#expect(presets.contains(.longFast))
		#expect(!presets.contains(.longSlow), "deprecated")
	}

	@Test("Without a map, the US keeps Turbo and loses the band-limited presets")
	func usWithoutMap() {
		let presets = ModemPresets.available(forRegion: .us, current: nil, supports2_8: true, regionInfo: nil)
		#expect(presets.contains(.longTurbo))
		#expect(presets.contains(.longFast))
		#expect(!presets.contains(.liteFast))
		#expect(!presets.contains(.tinyFast))
	}

	@Test("A region the app does not know is treated like one without band-limited presets")
	func unknownRegion() {
		let presets = ModemPresets.available(forRegion: nil, current: nil, supports2_8: true, regionInfo: nil)
		#expect(presets.contains(.longTurbo))
		#expect(!presets.contains(.liteFast))
	}

	@Test("The radio's map constrains the list")
	func mapConstrains() {
		let info = RegionPresetInfo(presets: [.longFast, .longTurbo], defaultPreset: .longTurbo, licensedOnly: false)
		let presets = ModemPresets.available(forRegion: .us, current: nil, supports2_8: true, regionInfo: info)
		#expect(Set(presets) == [.longFast, .longTurbo])
	}

	@Test("A map that matches nothing offered falls back to the region's own rules")
	func emptyIntersectionFallsBack() {
		// The EU strips Turbo first, so a map listing only Turbo would leave nothing to offer.
		let info = RegionPresetInfo(presets: [.longTurbo], defaultPreset: .longTurbo, licensedOnly: false)
		let presets = ModemPresets.available(forRegion: .eu868, current: nil, supports2_8: true, regionInfo: info)
		#expect(!presets.isEmpty)
		#expect(!presets.contains(.longTurbo))
	}

	@Test("Old firmware ignores the map and never offers the 2.8 presets")
	func oldFirmware() {
		let info = RegionPresetInfo(presets: [.liteFast, .longFast], defaultPreset: .longFast, licensedOnly: false)
		let presets = ModemPresets.available(forRegion: .eu868, current: nil, supports2_8: false, regionInfo: info)
		#expect(!presets.contains(.liteFast))
		#expect(presets.contains(.longFast))
		#expect(presets.contains(.shortFast))
	}

	@Test("A current preset the list already has is not repeated")
	func currentPresetNotDuplicated() {
		let presets = ModemPresets.available(forRegion: .us, current: .longFast, supports2_8: true, regionInfo: nil)
		#expect(presets.filter { $0 == .longFast }.count == 1)
	}
}
