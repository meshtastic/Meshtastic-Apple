//
//  ChannelPublicKeyTests.swift
//  MeshtasticTests
//

import Testing
import Foundation
@testable import Meshtastic
import MeshtasticProtobufs

@Suite("Channel public key")
struct ChannelPublicKeyTests {

	private static let privateKey16 = Data(repeating: 0x5A, count: 16)
	private static let privateKey32 = Data(repeating: 0x5A, count: 32)

	private static func defaultKey(lastByte: UInt8) -> Data {
		var key = ChannelIdentity.defaultPSK
		key[key.count - 1] = lastByte
		return key
	}

	@Test("An empty primary key is public")
	func emptyPrimary() {
		#expect(ChannelIdentity.usesPublicKey(Data()))
	}

	@Test("Every one byte key is public", arguments: [UInt8(0), 1, 2, 10, 255])
	func oneByte(index: UInt8) {
		#expect(ChannelIdentity.usesPublicKey(Data([index])))
		#expect(ChannelIdentity.usesPublicKey(Data([index]), primary: Self.privateKey32))
	}

	@Test("The expanded default key is public whatever its last byte", arguments: [UInt8(0x01), 0x02, 0x00, 0xFF])
	func expandedDefault(lastByte: UInt8) {
		#expect(ChannelIdentity.usesPublicKey(Self.defaultKey(lastByte: lastByte)))
	}

	@Test("A slice of a larger buffer is compared from its own start")
	func slicedKey() {
		let buffer = Data([0xAA, 0xBB]) + ChannelIdentity.defaultPSK
		#expect(ChannelIdentity.usesPublicKey(buffer.suffix(16)))
	}

	@Test("A 128 bit key that differs inside the first 15 bytes is private")
	func nearDefault() {
		var key = ChannelIdentity.defaultPSK
		key[14] ^= 0x01
		#expect(!ChannelIdentity.usesPublicKey(key))
	}

	@Test("Other keys are private")
	func privateKeys() {
		#expect(!ChannelIdentity.usesPublicKey(Self.privateKey16))
		#expect(!ChannelIdentity.usesPublicKey(Self.privateKey32))
		#expect(!ChannelIdentity.usesPublicKey(ChannelIdentity.defaultPSK.prefix(15)))
		#expect(!ChannelIdentity.usesPublicKey(ChannelIdentity.defaultPSK + ChannelIdentity.defaultPSK))
	}

	@Test("An empty secondary key follows the primary")
	func emptySecondary() {
		#expect(ChannelIdentity.usesPublicKey(Data(), primary: Data([1])))
		#expect(ChannelIdentity.usesPublicKey(Data(), primary: Data()))
		#expect(ChannelIdentity.usesPublicKey(Data(), primary: Self.defaultKey(lastByte: 0x05)))
		#expect(!ChannelIdentity.usesPublicKey(Data(), primary: Self.privateKey32))
		#expect(ChannelIdentity.usesPublicKey(Data(), primary: nil), "an unknown primary counts as public")
	}

	@Test("Precision is held to 15 only on a public key")
	func onWirePrecision() {
		#expect(ChannelIdentity.onWirePositionPrecision(32, usesPublicKey: true) == 15)
		#expect(ChannelIdentity.onWirePositionPrecision(16, usesPublicKey: true) == 15)
		#expect(ChannelIdentity.onWirePositionPrecision(15, usesPublicKey: true) == 15)
		#expect(ChannelIdentity.onWirePositionPrecision(13, usesPublicKey: true) == 13)
		#expect(ChannelIdentity.onWirePositionPrecision(0, usesPublicKey: true) == 0)
		#expect(ChannelIdentity.onWirePositionPrecision(32, usesPublicKey: false) == 32)
	}

	private func channel(role: Channel.Role, psk: Data, precision: UInt32?) -> Channel {
		var channel = Channel()
		channel.role = role
		channel.settings.psk = psk
		if let precision {
			channel.settings.moduleSettings.positionPrecision = precision
		}
		return channel
	}

	@Test("A primary ignores the primary key it is handed")
	func primaryIgnoresPrimaryKey() {
		var open = channel(role: .primary, psk: Data(), precision: 32)
		open.capPositionPrecisionForPublicKey(primaryPSK: Self.privateKey32)
		#expect(open.settings.moduleSettings.positionPrecision == 15)
	}

	@Test("A secondary with an empty key follows the primary key it is handed")
	func secondaryFollowsPrimaryKey() {
		var inheritsPrivate = channel(role: .secondary, psk: Data(), precision: 32)
		inheritsPrivate.capPositionPrecisionForPublicKey(primaryPSK: Self.privateKey32)
		#expect(inheritsPrivate.settings.moduleSettings.positionPrecision == 32)

		var inheritsPublic = channel(role: .secondary, psk: Data(), precision: 32)
		inheritsPublic.capPositionPrecisionForPublicKey(primaryPSK: Data([1]))
		#expect(inheritsPublic.settings.moduleSettings.positionPrecision == 15)
	}

	@Test("Absent module settings stay absent")
	func absentModuleSettings() {
		var bare = channel(role: .primary, psk: Data([1]), precision: nil)
		bare.capPositionPrecisionForPublicKey(primaryPSK: nil)
		#expect(!bare.settings.hasModuleSettings)
	}
}
