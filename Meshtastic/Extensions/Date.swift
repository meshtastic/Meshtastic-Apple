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
			return "unknown.age".localized
		}
	}
}
