//
//  ReceivedBy.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation

/// The `receivedBy` column of rows stored once for several radios: messages, positions,
/// telemetry, PAX, waypoints and trace routes (D-21, T452). Each radio is written as
/// `",<node number>,"` with the commas shared, so `",1,2,"` is radios 1 and 2 and a query can
/// match one radio with `contains(token(radio))`. Empty means not known yet: rows from before
/// feature 021 until the backfill reaches them. Those show for every radio.
enum ReceivedBy {
	/// What a query matches for `radio`.
	static func token(_ radio: Int64) -> String {
		",\(radio),"
	}

	/// `value` with `radio` added, unchanged when it's there already or `radio` is 0.
	static func adding(_ radio: Int64, to value: String) -> String {
		guard radio != 0, !contains(radio, in: value) else { return value }
		return value.isEmpty ? token(radio) : value + "\(radio),"
	}

	static func contains(_ radio: Int64, in value: String) -> Bool {
		value.contains(token(radio))
	}

	/// The radios in `value`.
	static func radios(in value: String) -> [Int64] {
		value.split(separator: ",").compactMap { Int64($0) }
	}

	/// True when `value` is empty or names `radio`: the row shows for `radio`.
	static func shows(_ value: String, for radio: Int64) -> Bool {
		value.isEmpty || contains(radio, in: value)
	}

	/// True when no radio but `radio` received the row (or none is known).
	static func onlyBy(_ radio: Int64, _ value: String) -> Bool {
		radios(in: value).allSatisfy { $0 == radio }
	}

	/// `value` with radio `old` renamed `new` (the 2.8 node number change, `NodeRenumber`).
	static func renumbering(_ value: String, from old: Int64, to new: Int64) -> String {
		guard contains(old, in: value) else { return value }
		let radios = radios(in: value).map { $0 == old ? new : $0 }
		var result = ""
		for radio in radios { result = adding(radio, to: result) }
		return result
	}
}
