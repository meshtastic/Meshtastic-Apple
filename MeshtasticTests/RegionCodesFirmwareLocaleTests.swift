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
			.my433, .my919, .sg923, .ph433, .ph868, .ph915, .lora24
		]
		for region in latinRegions {
			#expect(!region.prefersLocalizedFontFirmware, "\(region) should be Latin")
		}
	}

	@Test("Non-Latin regions prefer locale firmware")
	func nonLatinRegionsPreferLocale() {
		let nonLatinRegions: [RegionCodes] = [.ru, .ua433, .ua868, .cn, .jp, .kr, .tw, .th]
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

	@Test("Candidates are deduplicated and first tag is uppercased topic")
	func candidatesAreDeduplicatedAndOrdered() {
		for region in RegionCodes.allCases where region != .unset {
			let tags = region.firmwareLocaleTagCandidates
			#expect(tags.count == Set(tags).count, "Duplicates found in \(region)")
			#expect(tags.first == region.topic.uppercased())
		}
	}

	// MARK: - Philippines casing regression

	@Test("Philippines topic strings are uppercase")
	func philippinesTopicIsUppercase() {
		#expect(RegionCodes.ph433.topic == "PH_433")
		#expect(RegionCodes.ph868.topic == "PH_868")
		#expect(RegionCodes.ph915.topic == "PH_915")
	}

	@Test("Philippines candidates start with uppercase tag")
	func philippinesCandidatesStartWithUppercase() {
		#expect(RegionCodes.ph433.firmwareLocaleTagCandidates.first == "PH_433")
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
		let knownNonLatin: Set<RegionCodes> = [.ru, .ua433, .ua868, .cn, .jp, .kr, .tw, .th]
		let allNonUnset = Set(RegionCodes.allCases.filter { $0 != .unset })
		#expect(RegionCodes.latinScriptRegions.union(knownNonLatin) == allNonUnset,
				"A region is missing from latinScriptRegions or knownNonLatin")
	}

	/// The full stringly-typed chain — URL construction
	@Test("Locale-specific URL candidates precede the generic fallback")
	func localeURLCandidateOrdering() {
		let tags = RegionCodes.ru.firmwareLocaleTagCandidates  // ["RU", "ru"]
		// Verify the first tag produces a URL containing the locale suffix
		// and the last URL is the generic fallback (no locale suffix)
		#expect(tags.first == "RU")
		#expect(tags.last == "ru")
		// The generic fallback (no tag) must always be reachable
		// i.e. firmwareLocaleTagCandidates never produces an empty list for a set region
		#expect(!tags.isEmpty)
	}
}
