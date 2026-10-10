//
//  ChannelIdentity.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import CryptoKit
import Foundation
import MeshtasticProtobufs

/// Which channel a radio's channel slot really is, independent of the slot's index.
///
/// Two radios have "the same channel" when they would hear each other's traffic on it: the same
/// mesh (region, modulation and frequency, D-18), and the same name and encryption key, both as the
/// firmware resolves them. Channel indexes are just slots and differ from radio to radio, so
/// messages are grouped by this key instead (D-14).
///
/// Resolution mirrors the firmware (`Channels::getName` and `Channels::getKey`):
/// - an empty name means the modem preset's channel name when the radio uses a preset, and
///   "Custom" when it does not;
/// - a 1-byte PSK is shorthand: 0 means no encryption, 1 the well-known default key, and N the
///   default key with its last byte increased by N - 1;
/// - an empty PSK on a secondary channel means the primary channel's key; on the primary it means
///   no encryption;
/// - other short keys are zero-padded to 16 bytes, and keys between 17 and 31 bytes to 32.
enum ChannelIdentity {
	/// The firmware's `defaultpsk`, shared by every radio on a default channel.
	static let defaultKey: [UInt8] = [
		0xD4, 0xF1, 0xBB, 0x3A, 0x20, 0x29, 0x07, 0x59,
		0xF0, 0xBC, 0xFF, 0xAB, 0xCF, 0x4E, 0x69, 0x01
	]

	/// Prefix that versions the key format, so a future change can be told apart in stored data.
	/// `c2` keys are `c2:<mesh>:<key digest>:<name>`; `c1` keys had no mesh (T379).
	static let keyVersion = "c2"
	static let legacyKeyVersion = "c1"
	/// The mesh part of a key whose radio's LoRa settings aren't known.
	static let unknownMesh = "?"

	/// The channel's name as the firmware reports it on air and to MQTT.
	static func resolvedName(name: String?, usePreset: Bool, modemPreset: Int32) -> String {
		if let name, !name.isEmpty {
			return name
		}
		guard usePreset else { return "Custom" }
		return Config.LoRaConfig.ModemPreset(rawValue: Int(modemPreset))?.firmwareChannelName ?? "Custom"
	}

	/// The encryption key the firmware actually uses. Empty means no encryption.
	static func resolvedKey(psk: Data?, isSecondary: Bool, primaryPSK: Data? = nil) -> Data {
		let bytes = psk ?? Data()
		switch bytes.count {
		case 0:
			// A secondary channel with no key borrows the primary's. The primary cannot borrow.
			guard isSecondary, let primaryPSK else { return Data() }
			return resolvedKey(psk: primaryPSK, isSecondary: false)
		case 1:
			let index = bytes[bytes.startIndex]
			guard index != 0 else { return Data() }
			var key = defaultKey
			key[key.count - 1] = key[key.count - 1] &+ (index &- 1)
			return Data(key)
		case 2..<16:
			return bytes + Data(count: 16 - bytes.count)
		case 17..<32:
			return bytes + Data(count: 32 - bytes.count)
		default:
			return bytes
		}
	}

	/// A stable key for grouping: equal for any two channel slots that are the same channel.
	///
	/// `network` is the mesh the radio is on (D-18). Two radios with the same name and key but on
	/// different meshes can't hear each other on the channel, so it isn't the same channel (D-14,
	/// T379). Nil when the radio's LoRa settings aren't known; the key then says so.
	///
	/// Holds a short digest of the key, not the key itself, so it can be logged and indexed
	/// without spreading the channel secret around.
	// swiftlint:disable:next function_parameter_count
	static func key(name: String?, psk: Data?, isSecondary: Bool, primaryPSK: Data? = nil, usePreset: Bool, modemPreset: Int32, network: MeshNetwork?) -> String {
		let channelName = resolvedName(name: name, usePreset: usePreset, modemPreset: modemPreset)
		let keyPart = digest(of: resolvedKey(psk: psk, isSecondary: isSecondary, primaryPSK: primaryPSK))
		return [keyVersion, network?.identity ?? unknownMesh, keyPart, channelName].joined(separator: ":")
	}

	/// The `c1` key: name and key only, without the mesh. Kept to convert stored `c1` keys
	/// (`MultiRadioBackfill.rekeyLegacyMessages`).
	static func legacyKey(name: String?, psk: Data?, isSecondary: Bool, primaryPSK: Data? = nil, usePreset: Bool, modemPreset: Int32) -> String {
		let channelName = resolvedName(name: name, usePreset: usePreset, modemPreset: modemPreset)
		let keyPart = digest(of: resolvedKey(psk: psk, isSecondary: isSecondary, primaryPSK: primaryPSK))
		return "\(legacyKeyVersion):\(keyPart):\(channelName)"
	}

	/// The current key for a stored `c1` key whose mesh isn't known: it still groups with the other
	/// rows of that old channel, but with no radio's current channel.
	static func keyWithUnknownMesh(fromLegacy legacy: String) -> String? {
		guard isLegacy(legacy) else { return nil }
		return "\(keyVersion):\(unknownMesh):\(legacy.dropFirst(legacyKeyVersion.count + 1))"
	}

	/// True for a key stored before the mesh was part of it.
	static func isLegacy(_ key: String) -> Bool {
		key.hasPrefix("\(legacyKeyVersion):")
	}

	private static func digest(of channelKey: Data) -> String {
		guard !channelKey.isEmpty else { return "open" }
		return SHA256.hash(data: channelKey).prefix(8).map { String(format: "%02x", $0) }.joined()
	}

	// MARK: - Reading a key back (for the channel-change row, T377)

	/// The parts of a current key. Nil for a legacy or malformed key.
	struct Parts: Equatable {
		let mesh: String
		let keyDigest: String
		let name: String

		/// The modem preset, when the radio used one.
		var modemPreset: Int32? {
			MeshNetwork.modemPreset(fromIdentity: mesh)
		}
	}

	static func parts(of key: String) -> Parts? {
		let fields = key.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
		guard fields.count == 4, fields[0] == keyVersion else { return nil }
		return Parts(mesh: String(fields[1]), keyDigest: String(fields[2]), name: String(fields[3]))
	}
}

extension ChannelEntity {
	/// This slot's `ChannelIdentity` key. The LoRa settings come from the radio the channel
	/// belongs to; `primaryPSK` is that radio's primary channel key (used by secondaries with none),
	/// and `network` is that radio's mesh.
	func identityKey(primaryPSK: Data?, usePreset: Bool, modemPreset: Int32, network: MeshNetwork?) -> String {
		ChannelIdentity.key(
			name: name,
			psk: psk,
			isSecondary: role == Int32(Channel.Role.secondary.rawValue),
			primaryPSK: primaryPSK,
			usePreset: usePreset,
			modemPreset: modemPreset,
			network: network
		)
	}

	/// This slot's `c1` key, for converting rows stored with it.
	func legacyIdentityKey(primaryPSK: Data?, usePreset: Bool, modemPreset: Int32) -> String {
		ChannelIdentity.legacyKey(
			name: name,
			psk: psk,
			isSecondary: role == Int32(Channel.Role.secondary.rawValue),
			primaryPSK: primaryPSK,
			usePreset: usePreset,
			modemPreset: modemPreset
		)
	}
}
