//
//  NodeNameLimits.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/4/26.
//

import Foundation

/// How long a name the user can actually keep.
///
/// These are the nanopb buffer sizes minus the terminator, not the wire field sizes.
/// `User.long_name` carries 39 bytes on the wire, but a 2.8 radio stores every node it hears
/// in `NodeInfoLite`, whose `long_name` is 25 bytes including the terminator, and truncates
/// anything longer on the way in. A longer name would come back shortened from every radio
/// that stored it, including the user's own, so it is not worth letting them type it.
enum NodeNameLimits {

	/// Long name on 2.8 and later, in UTF-8 bytes: `NodeInfoLite.long_name` is 25 including
	/// the terminator.
	static let longNameBytes = 24

	/// Long name before 2.8, in UTF-8 bytes. Those radios store peers in `UserLite`, whose
	/// `long_name` is 40 including the terminator, so nothing is truncated until 2.8.
	static let legacyLongNameBytes = 39

	/// The limit for the radio being edited. A 2.8 radio truncates on store; an older one
	/// keeps the wire length. Note this is about the radio holding the name — a 2.8 node that
	/// hears an older one still stores only 24 of it.
	static func longNameBytes(storesCompactNames: Bool) -> Int {
		storesCompactNames ? longNameBytes : legacyLongNameBytes
	}

	/// Trims to `maxBytes` of UTF-8 without splitting a character. Counting bytes rather than
	/// characters is the point: one emoji is four bytes, and the radio truncates by bytes.
	static func trimmed(_ value: String, toBytes maxBytes: Int) -> String {
		guard value.utf8.count > maxBytes else { return value }
		var result = ""
		for character in value {
			guard result.utf8.count + String(character).utf8.count <= maxBytes else { break }
			result.append(character)
		}
		return result
	}
}
