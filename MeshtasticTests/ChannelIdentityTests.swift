//
//  ChannelIdentityTests.swift
//  MeshtasticTests
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import MeshtasticProtobufs
import Testing
@testable import Meshtastic

@Suite("Channel identity")
struct ChannelIdentityTests {
	private let longFast = Int32(Config.LoRaConfig.ModemPreset.longFast.rawValue)
	private let mediumFast = Int32(Config.LoRaConfig.ModemPreset.mediumFast.rawValue)
	private let defaultShorthand = Data([0x01])

	private func key(_ name: String?, _ psk: Data?, secondary: Bool = false, primary: Data? = nil, usePreset: Bool = true, preset: Int32? = nil) -> String {
		ChannelIdentity.key(name: name, psk: psk, isSecondary: secondary, primaryPSK: primary, usePreset: usePreset, modemPreset: preset ?? longFast)
	}

	// MARK: - The default channel

	@Test func unnamedDefaultChannelIsNamedAfterThePreset() {
		#expect(ChannelIdentity.resolvedName(name: "", usePreset: true, modemPreset: longFast) == "LongFast")
		#expect(ChannelIdentity.resolvedName(name: nil, usePreset: true, modemPreset: mediumFast) == "MediumFast")
	}

	@Test func defaultChannelIsTheSameOnEveryRadio() {
		#expect(key("", defaultShorthand) == key(nil, defaultShorthand))
	}

	@Test func explicitPresetNameAndFullDefaultKeyIsTheSameChannel() {
		// On air the firmware hashes the resolved name and key, so spelling both out is the same channel.
		#expect(key("LongFast", Data(ChannelIdentity.defaultKey)) == key("", defaultShorthand))
	}

	@Test func unnamedPrimaryOnDifferentPresetsIsDifferent() {
		#expect(key("", defaultShorthand, preset: longFast) != key("", defaultShorthand, preset: mediumFast))
	}

	@Test func withoutAPresetAnUnnamedChannelIsCustom() {
		#expect(ChannelIdentity.resolvedName(name: "", usePreset: false, modemPreset: longFast) == "Custom")
		#expect(key("", defaultShorthand, usePreset: false) == key("", defaultShorthand, usePreset: false, preset: mediumFast))
	}

	// MARK: - Custom channels

	@Test func sameNameAndKeyIsTheSameChannel() {
		let psk = Data((0..<32).map { UInt8($0) })
		#expect(key("Hikers", psk) == key("Hikers", psk, preset: mediumFast))
	}

	@Test func sameNameWithADifferentKeyIsDifferent() {
		let first = Data((0..<32).map { UInt8($0) })
		var second = first
		second[31] ^= 0xFF
		#expect(key("Hikers", first) != key("Hikers", second))
	}

	@Test func differentNameWithTheSameKeyIsDifferent() {
		let psk = Data((0..<16).map { UInt8($0) })
		#expect(key("Hikers", psk) != key("Bikers", psk))
	}

	@Test func namesAreCaseSensitiveLikeTheFirmwareHash() {
		#expect(key("hikers", defaultShorthand) != key("Hikers", defaultShorthand))
	}

	// MARK: - Key shorthand and padding

	@Test func shorthandIndexShiftsTheDefaultKeysLastByte() {
		let second = ChannelIdentity.resolvedKey(psk: Data([0x02]), isSecondary: false)
		#expect(second.count == 16)
		#expect(second.last == ChannelIdentity.defaultKey.last! + 1)
		#expect(key("", Data([0x02])) != key("", defaultShorthand))
	}

	@Test func shorthandZeroAndEmptyPrimaryMeanNoEncryption() {
		#expect(ChannelIdentity.resolvedKey(psk: Data([0x00]), isSecondary: false).isEmpty)
		#expect(ChannelIdentity.resolvedKey(psk: Data(), isSecondary: false).isEmpty)
		#expect(ChannelIdentity.resolvedKey(psk: nil, isSecondary: false).isEmpty)
		#expect(key("Open", Data([0x00])) == key("Open", nil))
		#expect(key("Open", nil).contains(":open:"))
	}

	@Test func secondaryWithoutAKeyUsesThePrimaryKey() {
		let primary = Data((0..<32).map { UInt8($0) })
		#expect(key("Side", nil, secondary: true, primary: primary) == key("Side", primary))
		#expect(key("Side", nil, secondary: true, primary: defaultShorthand) == key("Side", defaultShorthand))
	}

	@Test func shortKeysArePaddedLikeTheFirmware() {
		#expect(ChannelIdentity.resolvedKey(psk: Data([1, 2, 3]), isSecondary: false).count == 16)
		#expect(ChannelIdentity.resolvedKey(psk: Data(count: 20), isSecondary: false).count == 32)
		#expect(key("Pad", Data([1, 2, 3])) == key("Pad", Data([1, 2, 3]) + Data(count: 13)))
	}

	// MARK: - Format

	@Test func keyNeverContainsTheSecret() {
		let psk = Data((0..<32).map { UInt8($0) })
		let value = key("Hikers", psk)
		#expect(value.hasPrefix("\(ChannelIdentity.keyVersion):"))
		#expect(!value.contains(psk.map { String(format: "%02x", $0) }.joined()))
	}

	@Test func entityKeyReadsTheRoleAndSettings() {
		let channel = ChannelEntity()
		channel.name = "Side"
		channel.psk = nil
		channel.role = Int32(Channel.Role.secondary.rawValue)
		let primary = Data((0..<16).map { UInt8($0) })
		#expect(channel.identityKey(primaryPSK: primary, usePreset: true, modemPreset: longFast) == key("Side", primary))
	}
}
