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

	/// Long name, in UTF-8 bytes.
	static let longNameBytes = 24

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
