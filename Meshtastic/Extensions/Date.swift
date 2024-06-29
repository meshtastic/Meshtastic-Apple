//
//  Date.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation

extension Date {

	func formattedDate(format: String) -> String {
		let dateformat = DateFormatter()
		dateformat.dateFormat = format
		if self > Calendar.current.date(byAdding: .year, value: -5, to: Date())! {
			return dateformat.string(from: self)
		} else {
			return NSLocalizedString("unknown.age", comment: "No comment provided")
		}
	}
	func relativeTimeOfDay() -> String {
		let hour = Calendar.current.component(.hour, from: self)

		switch hour {
		case 6..<12: return NSLocalizedString("relativetimeofday.morning", comment: "No comment provided")
		case 12: return NSLocalizedString("relativetimeofday.midday", comment: "No comment provided")
		case 13..<17: return NSLocalizedString("relativetimeofday.afternoon", comment: "No comment provided")
		case 17..<22: return NSLocalizedString("relativetimeofday.evening", comment: "No comment provided")
		default: return NSLocalizedString("relativetimeofday.nighttime", comment: "No comment provided")
		}
	}
}
