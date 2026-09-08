//
//  NodeSecurityIndicator.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/7/26.
//

import SwiftUI

/// Which security indicator a node-list row shows beside the node's name.
///
/// Firmware 2.8 introduced signed NodeInfo broadcasts, and whether the radio verified a node's
/// signature says more about that node's security than whether a public key happens to be on
/// file. Rows for nodes reporting firmware 2.8 or newer therefore show signing state (signed or
/// not signed) instead of the PKI lock. Nodes on older firmware — or with no reported version —
/// keep the locks. A key mismatch is a real warning at any version and is never hidden.
enum NodeSecurityIndicator: Equatable {
	/// 2.8+: the user verified this node's key in person (contact QR exchange or the radio's
	/// verification flow). The strongest trust the list can show.
	case verified
	/// 2.8+: the node's NodeInfo broadcast carried an XEdDSA signature the radio verified.
	/// Every 2.8 node signs, so this is the baseline for that firmware.
	case signed
	/// Pre-2.8 or unknown firmware: a public key is on file and matches.
	case publicKey
	/// Pre-2.8 or unknown firmware: no public key on file; direct messages use the channel key.
	case sharedKey
	/// Any version: the node's latest key does not match the stored one. Always shown.
	case keyMismatch

	/// The SF Symbol and color the row renders for this state.
	var glyph: (image: String, color: Color) {
		switch self {
		case .verified:
			return ("person.badge.shield.checkmark", .green)
		case .signed:
			return (SignedNodeIcon.symbolName, .secondary)
		case .publicKey:
			return ("lock.fill", .green)
		case .sharedKey:
			return ("lock.open.fill", .yellow)
		case .keyMismatch:
			return ("key.slash", .red)
		}
	}

	/// True when the node's reported firmware version is known and is 2.8.0 or newer.
	///
	/// Strict on unknown — unlike the permissive capability gates (see
	/// `NodeInfoEntity.firmwareSupportsStatusMessage`), a node with no reported version keeps the
	/// familiar locks rather than being credited with signing support it may not have.
	static func supportsSigning(firmwareVersion: String?) -> Bool {
		guard let version = firmwareVersion, !version.isEmpty else { return false }
		let comparison = "2.8.0".compare(version, options: .numeric)
		return comparison == .orderedAscending || comparison == .orderedSame
	}

	/// Decides the indicator for one row from snapshot fields alone (no live model access).
	static func status(firmwareVersion: String?, pkiEncrypted: Bool, keyMatch: Bool, verified: Bool = false, isOwnNode: Bool = false) -> NodeSecurityIndicator {
		// A stored key that stopped matching is a warning regardless of firmware version —
		// most of all for a contact the user personally verified.
		if pkiEncrypted && !keyMatch {
			return .keyMismatch
		}
		if supportsSigning(firmwareVersion: firmwareVersion) {
			// Every 2.8 node signs its broadcasts, so a 2.8 node is signed by definition.
			// The connected radio is the user's own device: they hold its key, so its
			// identity needs no third-party verification. Sharing your own contact QR
			// already marks it manually verified on the same reasoning.
			return (verified || isOwnNode) ? .verified : .signed
		}
		return pkiEncrypted ? .publicKey : .sharedKey
	}
}
