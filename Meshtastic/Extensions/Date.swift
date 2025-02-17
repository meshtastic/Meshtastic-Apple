//
//  Date.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation

extension Date {

	var lastHeard: String {
		if timeIntervalSince1970 > 0 {
			formatted()
		} else {
			"unknown"
		}
	}

	func formattedDate(format: String) -> String {
		let dateformat = DateFormatter()
		dateformat.dateFormat = format
		if self > Calendar.current.date(byAdding: .year, value: -5, to: Date())! {
			return dateformat.string(from: self)
		} else {
			return "unknown.age".localized
		}
	}
	func relativeTimeOfDay() -> String {
		let hour = Calendar.current.component(.hour, from: self)

		switch hour {
		case 6..<12: return "relativetimeofday.morning".localized
		case 12: return "relativetimeofday.midday".localized
		case 13..<17: return "relativetimeofday.afternoon".localized
		case 17..<22: return "relativetimeofday.evening".localized
		default: return "relativetimeofday.nighttime".localized
		}
	}
}
