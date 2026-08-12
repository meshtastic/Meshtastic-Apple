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

	/// Builds a cached, POSIX-locale `DateFormatter` for filename stamps. Reused so the formatter
	/// boilerplate isn't repeated (and re-allocated) at each call site.
	private static func exportFormatter(_ format: String) -> DateFormatter {
		let formatter = DateFormatter()
		formatter.dateFormat = format
		formatter.locale = Locale(identifier: "en_US_POSIX")
		return formatter
	}

	private static let exportTimestampFormatter = exportFormatter("yyyy-MM-dd_HHmmss")
	private static let exportDateStampFormatter = exportFormatter("yyyyMMdd")

	/// Filename-safe timestamp: `2026-05-04_101521`
	var exportTimestamp: String {
		Date.exportTimestampFormatter.string(from: self)
	}

	/// Android-style filename date stamp: `20260504` (matches the `.cfg` export naming used by the Android app).
	var exportDateStamp: String {
		Date.exportDateStampFormatter.string(from: self)
	}
}
