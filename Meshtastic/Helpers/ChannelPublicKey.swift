//
//  ChannelPublicKey.swift
//  Meshtastic
//

import Foundation
import MeshtasticProtobufs

extension ChannelIdentity {

	/// The most position precision a channel anyone can decrypt may carry.
	static let maxPublicKeyPositionPrecision: UInt32 = 15

	/// Whether anyone can decrypt a channel with this stored key, by the firmware's
	/// `channelFileUsesPublicKey` rule.
	///
	/// - Parameter primary: the primary channel's stored key when `psk` belongs to a secondary,
	///   which uses the primary's key when its own is empty. Pass `nil` for the primary itself, or
	///   when the primary is unknown, which counts as public.
	static func usesPublicKey(_ psk: Data, primary: Data? = nil) -> Bool {
		switch psk.count {
		case 0:
			return primary.map { usesPublicKey($0) } ?? true
		case 1:
			return true
		case 2..<defaultPSK.count:
			// The radio pads a short key with zeros, which can land in the default key family.
			return usesPublicKey(psk + Data(count: defaultPSK.count - psk.count))
		case defaultPSK.count:
			// The last byte picks a member of the default key family, so it is not compared.
			return psk.prefix(defaultPSK.count - 1) == defaultPSK.prefix(defaultPSK.count - 1)
		default:
			return false
		}
	}

	/// `precision` held to the public key ceiling when the channel uses a public key.
	static func onWirePositionPrecision(_ precision: UInt32, usesPublicKey: Bool) -> UInt32 {
		usesPublicKey ? min(precision, maxPublicKeyPositionPrecision) : precision
	}
}

extension Channel {

	/// Holds `position_precision` to the public key ceiling when this channel uses a public key.
	/// Module settings that are absent stay absent.
	///
	/// - Parameter primaryPSK: the primary channel's stored key, read only for a secondary.
	mutating func capPositionPrecisionForPublicKey(primaryPSK: Data?) {
		guard hasSettings, settings.hasModuleSettings, role != .disabled else { return }
		let isPublic = ChannelIdentity.usesPublicKey(settings.psk, primary: role == .primary ? nil : primaryPSK)
		let capped = ChannelIdentity.onWirePositionPrecision(settings.moduleSettings.positionPrecision, usesPublicKey: isPublic)
		if capped != settings.moduleSettings.positionPrecision {
			settings.moduleSettings.positionPrecision = capped
		}
	}
}
