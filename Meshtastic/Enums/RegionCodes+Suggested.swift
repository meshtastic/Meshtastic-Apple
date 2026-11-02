//
//  RegionCodes+Suggested.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//

import Foundation

extension RegionCodes {
	/// The region most radios run on in a country, from its ISO 3166 code, so the radio
	/// setup can start on the one the phone's region setting points at. Nil where there is
	/// no clear answer; the user then picks.
	static func suggested(forCountryCode code: String) -> RegionCodes? {
		switch code.uppercased() {
		case "US", "CA", "MX":
			return .us
		case "BR":
			return .br902
		case "CN":
			return .cn
		case "JP":
			return .jp
		case "AU", "NZ":
			return .anz
		case "KR":
			return .kr
		case "TW":
			return .tw
		case "RU":
			return .ru
		case "IN":
			return .in
		case "TH":
			return .th
		case "MY":
			return .my919
		case "SG":
			return .sg923
		case "PH":
			return .ph915
		case "KZ":
			return .kz863
		case "NP":
			return .np865
		case "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT",
			 "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
			 "GB", "CH", "NO", "IS", "LI", "AL", "BA", "ME", "MK", "RS", "XK", "MD", "TR", "ZA":
			return .eu868
		default:
			return nil
		}
	}

	/// The suggestion for a locale's region setting; nil for a locale without one.
	static func suggested(for locale: Locale) -> RegionCodes? {
		guard let code = locale.region?.identifier else { return nil }
		return suggested(forCountryCode: code)
	}
}
