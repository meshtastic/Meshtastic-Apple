//
//  NodeNameLimitsTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/4/26.
//

import Testing
import Foundation
@testable import Meshtastic

/// 2.8 radios store every node they hear in `NodeInfoLite`, whose `long_name` is 25 bytes
/// including the terminator. A name longer than 24 bytes is truncated on the way in, so the
/// app must not let one be typed — it would come back shortened from the user's own radio.
@Suite("Node name limits")
struct NodeNameLimitsTests {

	@Test("Long name is capped at what a 2.8 radio will store")
	func longNameCap() {
		#expect(NodeNameLimits.longNameBytes == 24)
	}

	@Test("Older radios keep the wire length")
	func legacyCap() {
		// Before 2.8 a radio stores peers in UserLite, whose long_name is 40 including the
		// terminator, so nothing was truncated.
		#expect(NodeNameLimits.legacyLongNameBytes == 39)
		#expect(NodeNameLimits.longNameBytes(storesCompactNames: false) == 39)
		#expect(NodeNameLimits.longNameBytes(storesCompactNames: true) == 24)
	}

	@Test("A name that fits an older radio is not trimmed for it")
	func legacyNameSurvives() {
		let name = String(repeating: "a", count: 30)
		#expect(NodeNameLimits.trimmed(name, toBytes: NodeNameLimits.longNameBytes(storesCompactNames: false)) == name)
		#expect(NodeNameLimits.trimmed(name, toBytes: NodeNameLimits.longNameBytes(storesCompactNames: true)).utf8.count == 24)
	}

	@Test("A name at the limit is left alone")
	func atTheLimit() {
		let name = String(repeating: "a", count: 24)
		#expect(NodeNameLimits.trimmed(name, toBytes: 24) == name)
	}

	@Test("A name over the limit is trimmed to it")
	func overTheLimit() {
		let trimmed = NodeNameLimits.trimmed(String(repeating: "a", count: 40), toBytes: 24)
		#expect(trimmed.utf8.count == 24)
	}

	@Test("Trimming counts bytes, not characters")
	func countsBytes() {
		// Each of these is 4 UTF-8 bytes, so six fit and the seventh does not.
		let trimmed = NodeNameLimits.trimmed(String(repeating: "🛰", count: 10), toBytes: 24)
		#expect(trimmed.utf8.count == 24)
		#expect(trimmed.count == 6)
	}

	@Test("A character is never split at the boundary")
	func neverSplitsACharacter() {
		// 22 bytes of ASCII plus a 4-byte emoji would be 26; the emoji has to go whole.
		let name = String(repeating: "a", count: 22) + "🛰"
		let trimmed = NodeNameLimits.trimmed(name, toBytes: 24)
		#expect(trimmed == String(repeating: "a", count: 22))
		#expect(trimmed.utf8.count == 22, "stops short rather than emitting a partial character")
	}

	@Test("A Ham name always fits")
	func hamNameFits() {
		// Call sign 7 + "//" + descriptive name 14 = 23, inside the long name limit.
		let composed = HamName(
			callSign: String(repeating: "W", count: HamName.maxCallSignBytes),
			longName: String(repeating: "n", count: HamName.maxLongNameBytes)
		).composed
		#expect(composed.utf8.count <= NodeNameLimits.longNameBytes)
	}
}
