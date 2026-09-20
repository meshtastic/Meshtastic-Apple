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

	// A row is on screen before the radio's values arrive: the form fills the message
	// after load(). Seeding a field once on appear leaves it empty and, if blank counts
	// as invalid, red — which is what shipped to a device and showed an empty key in red.
	@Test("A key that has not arrived yet is not an error")
	func blankIsNotAFault() {
		#expect(SecurityKey.isValid(""), "an empty field is unset or still loading, not wrong")
		#expect(!SecurityKey.isValid("AAAA"), "text that is present and not a key is wrong")
	}

	// The private key field and the three admin slots share one rule for taking up a
	// value that arrives late, so they share one function and this tests that, rather
	// than a copy of its condition that would keep passing if the rows stopped using it.
	@Test("A field seeded before the values arrive still picks them up")
	func lateValuesAreAdopted() {
		let arriving = key(0x5A)
		#expect(SecurityKey.shouldAdopt(arriving, into: ""),
				"the key must appear once it loads")
		#expect(!SecurityKey.shouldAdopt(arriving, into: SecurityKey.text(arriving)),
				"a field already holding that key is left alone")
		#expect(SecurityKey.shouldAdopt(arriving, into: SecurityKey.text(key(0x77))),
				"a field holding some other key follows the radio")
		#expect(!SecurityKey.shouldAdopt(Data(), into: ""),
				"nothing arriving into a blank field is not a change")
	}

	@Test("A key being typed is not overwritten under the cursor")
	func partialTextSurvivesAnArrival() {
		// Half a key reads as unset, so the plain "does this text mean that key" check
		// would call it stale and replace what the user is still typing.
		#expect(!SecurityKey.shouldAdopt(key(0x5A), into: "AAAA"))
		#expect(!SecurityKey.shouldAdopt(Data(), into: "AAAA"))
	}

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
		// The bridge the form loads through. A swap here authorizes a different key than
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

	@Test("Clearing one slot leaves the others where they were")
	func clearingASlotKeepsThePositions() {
		var config = Config.SecurityConfig()
		config.adminKey = [key(0x11), key(0x22), key(0x33)]
		config.setAdminKey(Data(), at: 1)
		#expect(config.adminKey == [key(0x11), Data(), key(0x33)],
				"a cleared slot holds its place, or the tertiary key becomes the secondary")
	}

	@Test("Managed mode goes with the last admin key")
	func managedModeNeedsAnAdministrator() {
		// A managed node with no administrator cannot be changed back: its owner is
		// locked out of settings and there is no key left to sign a remote change with.
		var config = Config.SecurityConfig()
		config.adminKey = [key(0x11), Data(), Data()]
		config.isManaged = true

		config.setAdminKey(key(0x22), at: 1)
		#expect(config.isManaged, "another administrator is still an administrator")

		config.setAdminKey(Data(), at: 1)
		#expect(config.isManaged, "the primary key is still set")

		config.setAdminKey(Data(), at: 0)
		#expect(!config.isManaged, "the last key went, so managed mode goes with it")
		#expect(config.adminKey.count == SecurityKey.slots)
	}

}
