//
//  RegionCodesFirmwareLocaleTests.swift
//  Meshtastic
//
//  Created by laconicman on 5/18/26.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("RegionCodes+FirmwareLocale")
struct RegionCodesFirmwareLocaleTests {

	// MARK: - prefersLocalizedFontFirmware

	@Test("Latin regions do not prefer locale firmware")
	func latinRegionsDoNotPreferLocale() {
		let latinRegions: [RegionCodes] = [
			.us, .eu433, .eu868, .anz, .in, .nz865,
			.my433, .my919, .sg923, .ph433, .ph868, .ph915, .lora24,
			.anz433, .kz433, .kz863, .np865, .br902,
			.eu866, .eu874, .eu917, .euN868,
			.itu12M, .itu22M, .itu32M, .itu170Cm, .itu270Cm, .itu370Cm, .itu2125Cm
		]
		for region in latinRegions {
			#expect(!region.prefersLocalizedFontFirmware, "\(region) should be Latin")
		}
	}

	@Test("Non-Latin regions prefer locale firmware")
	func nonLatinRegionsPreferLocale() {
		let nonLatinRegions: [RegionCodes] = [.ru, .ua433, .cn, .jp, .kr, .tw, .th]
		for region in nonLatinRegions {
			#expect(region.prefersLocalizedFontFirmware, "\(region) should be non-Latin")
		}
	}

	@Test("Unset region does not prefer locale firmware")
	func unsetDoesNotPreferLocale() {
		#expect(!RegionCodes.unset.prefersLocalizedFontFirmware)
	}

	// MARK: - firmwareLocaleTagCandidates

	@Test("Simple region produces two candidates")
	func simpleRegionCandidates() {
		#expect(RegionCodes.ru.firmwareLocaleTagCandidates == ["RU", "ru"])
	}

	@Test("Compound region expands to six candidates")
	func compoundRegionCandidates() {
		#expect(RegionCodes.ua433.firmwareLocaleTagCandidates == ["UA_433", "ua_433", "UA-433", "ua-433", "UA", "ua"])
	}

	// MARK: - More general checks

	@Test("All region topics are uppercase")
	/// `topic` is always uppercase — the root invariant
	func allTopicsAreUppercase() {
		for region in RegionCodes.allCases {
			#expect(region.topic == region.topic.uppercased(),
					"\(region).topic '\(region.topic)' is not uppercase")
		}
	}

	/// latinScriptRegions exhaustiveness — the "new region" trap
	@Test("All non-unset regions are explicitly classified as Latin or non-Latin")
	func allRegionsAreExplicitlyClassified() {
		let knownNonLatin: Set<RegionCodes> = [.ru, .ua433, .cn, .jp, .kr, .tw, .th]
		let allNonUnset = Set(RegionCodes.allCases.filter { $0 != .unset })
		#expect(RegionCodes.latinScriptRegions.union(knownNonLatin) == allNonUnset,
				"A region is missing from latinScriptRegions or knownNonLatin")
	}

	/// The full stringly-typed chain — URL construction
	@Test("Locale tag candidates are non-empty and well-formed for all set regions",
		  arguments: RegionCodes.allCases.filter { $0 != .unset })
	func localeTagCandidatesForRegion(region: RegionCodes) {
		let tags = region.firmwareLocaleTagCandidates
		#expect(!tags.isEmpty, "\(region) should produce at least one tag")
		#expect(tags.first == region.topic.uppercased(),
				"\(region) first tag should be uppercased topic")
		#expect(tags.count == Set(tags).count,
				"\(region) should have no duplicate tags")
	}

	// MARK: - Some specific tests

	@Test("Philippines topic strings are uppercase and properly formatted with `_`")
	func philippinesTopicIsUppercase() {
		#expect(RegionCodes.ph433.topic == "PH_433")
		#expect(RegionCodes.ph868.topic == "PH_868")
		#expect(RegionCodes.ph915.topic == "PH_915")
	}
}
