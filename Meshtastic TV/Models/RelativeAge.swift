//
//  RelativeAge.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 8/19/26.
//
//  Compact "how long ago" text for the wall display.
//

import Foundation

enum RelativeAge {

	/// "0s ago", "12s ago", "4m ago", "3h ago".
	///
	/// Sub-minute is formatted by hand because `.relative` rounds a just-arrived
	/// sample to zero and then picks future tense — a node heard a moment ago read
	/// as "in 0 sec.", which looks like a countdown. Above a minute the system
	/// formatter is used so the units stay localized.
	static func text(since date: Date, now: Date = Date()) -> String {
		let elapsed = max(0, now.timeIntervalSince(date))
		if elapsed < 60 {
			return "\(Int(elapsed))s ago"
		}
		return date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
	}
}
