//
//  RegionCodes+FirmwareLocale.swift
//  Meshtastic
//
//  Region-aware firmware artifact selection (PR #1827, @laconicman).
//  Some regions imply a non-Latin display language, and firmware releases can
//  ship locale-tagged variants with the right on-device fonts (e.g.
//  firmware-tbeam-2.7.0-RU.bin). These helpers classify regions and produce
//  candidate locale tags to try before falling back to the generic artifact.
//
import Foundation

extension RegionCodes {
	/// Regions whose default display language renders fine with the generic
	/// (Latin-font) firmware. Everything else prefers a locale-tagged variant.
	/// Keep exhaustive: RegionCodesFirmwareLocaleTests fails when a new region
	/// is added without classifying it here or in the test's non-Latin list.
	static let latinScriptRegions: Set<RegionCodes> = [
		.us, .eu433, .eu868, .anz, .anz433, .in, .nz865, .my433, .my919,
		.sg923, .ph433, .ph868, .ph915, .kz433, .kz863, .np865, .br902,
		.eu866, .eu874, .eu917, .euN868, .lora24,
		.itu12M, .itu22M, .itu32M, .itu170Cm, .itu270Cm, .itu370Cm, .itu2125Cm
	]

	var prefersLocalizedFontFirmware: Bool {
		!Self.latinScriptRegions.contains(self) && self != .unset
	}

	/// Locale tags to try in firmware artifact filenames, most specific first.
	/// Derived from `topic` (e.g. "UA_433" → UA_433, ua_433, UA-433, ua-433, UA, ua).
	var firmwareLocaleTagCandidates: [String] {
		let primary = topic.uppercased()
		var tags: [String] = []

		func append(_ value: String?) {
			guard let value, !value.isEmpty, !tags.contains(value) else { return }
			tags.append(value)
		}

		append(primary)
		append(primary.lowercased())
		append(primary.replacingOccurrences(of: "_", with: "-"))
		append(primary.lowercased().replacingOccurrences(of: "_", with: "-"))

		if let firstSegment = primary.split(separator: "_").first.map(String.init) {
			append(firstSegment)
			append(firstSegment.lowercased())
		}

		return tags
	}
}
