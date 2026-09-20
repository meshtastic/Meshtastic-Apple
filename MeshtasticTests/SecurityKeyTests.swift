//
//  SecurityKeyTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import Testing
import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

/// The admin keys are three stored columns and one positional array, converted in both
/// directions. Getting that wrong moves or drops a key, which changes who is allowed to
/// administer the node, so it is worth pinning rather than trusting.
@Suite("Security keys")
struct SecurityKeyTests {

	private func key(_ byte: UInt8) -> Data { Data(repeating: byte, count: SecurityKey.byteCount) }

	@Test("A key round-trips through text unchanged")
	func keyRoundTrips() {
		let original = key(0xAB)
		#expect(SecurityKey.data(SecurityKey.text(original)) == original)
		#expect(SecurityKey.text(Data()) == "", "an unset key reads as blank, not as base64 of nothing")
	}

	@Test("Only a full-length key counts")
	func onlyFullLengthKeysCount() {
		#expect(SecurityKey.isValid(""), "blank means unset")
		#expect(SecurityKey.isValid(key(0x01).base64EncodedString()))
		// A short key is a typo. Storing it would cost every existing conversation.
		#expect(!SecurityKey.isValid(Data(repeating: 1, count: 16).base64EncodedString()))
		#expect(!SecurityKey.isValid("not base64 at all"))
		#expect(SecurityKey.data("not base64 at all").isEmpty)
	}

	@Test("An empty slot keeps its place")
	func emptySlotsHoldTheirPosition() {
		// The firmware reads the array positionally. If a blank primary collapsed, the
		// secondary key would become the primary administrator.
		let padded = SecurityKey.padded([Data(), key(0x02)])
		#expect(padded.count == SecurityKey.slots)
		#expect(padded[0].isEmpty)
		#expect(padded[1] == key(0x02))
		#expect(padded[2].isEmpty)
	}

	@Test("More keys than slots are not silently kept")
	func extraKeysAreDropped() {
		let padded = SecurityKey.padded([key(1), key(2), key(3), key(4)])
		#expect(padded.count == SecurityKey.slots)
		#expect(padded.last == key(3))
	}

	@Test("The three stored columns become the array in order")
	func entityBridgeKeepsOrder() {
		// The bridge the form loads through. A swap here authorises a different key than
		// the one the user put in the primary slot.
		let entity = SecurityConfigEntity()
		entity.adminKey = key(0x11)
		entity.adminKey2 = key(0x22)
		entity.adminKey3 = key(0x33)
		entity.publicKey = key(0xAA)
		entity.privateKey = key(0xBB)

		let config = Config.SecurityConfig(entity: entity)
		#expect(config.adminKey == [key(0x11), key(0x22), key(0x33)])
		#expect(config.publicKey == key(0xAA))
		#expect(config.privateKey == key(0xBB))
	}

	@Test("A node with no admin keys still has three slots")
	func absentKeysBecomeEmptySlots() {
		let entity = SecurityConfigEntity()
		let config = Config.SecurityConfig(entity: entity)
		#expect(config.adminKey.count == SecurityKey.slots)
		let allEmpty = config.adminKey.allSatisfy { $0.isEmpty }
		#expect(allEmpty)
	}
}
