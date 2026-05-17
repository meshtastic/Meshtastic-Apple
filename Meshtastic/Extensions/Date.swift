//
//  Date.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation

extension Date {

	var lastHeard: String {
		if self.timeIntervalSince1970 > 0 && self < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {
			formatted(date: .numeric, time: .shortened)
		} else {
			"Unknown Age".localized
		}
	}

	func formattedDate(format: String) -> String {
		guard self.timeIntervalSince1970 > 0 else {
			return "Unknown Age".localized
		}
		let formatter = DateFormatter()
		formatter.dateFormat = format
		return formatter.string(from: self)
	}

	func relativeTimeOfDay() -> String {
		let hour = Calendar.current.component(.hour, from: self)

		switch hour {
		case 6..<12: return "Morning".localized
		case 12: return "Midday".localized
		case 13..<17: return "Afternoon".localized
		case 17..<22: return "Evening".localized
		default: return "Nighttime".localized
		}
	}

	/// Filename-safe timestamp: `2026-05-04_101521`
	var exportTimestamp: String {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd_HHmmss"
		formatter.locale = Locale(identifier: "en_US_POSIX")
		return formatter.string(from: self)
	}
}
