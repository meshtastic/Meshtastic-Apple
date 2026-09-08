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
	/// 2.8+: the node's NodeInfo broadcast carried an XEdDSA signature the radio verified.
	case signed
	/// 2.8+: the node's broadcasts are not signed. Honest and neutral — common, not an alarm.
	case notSigned
	/// Pre-2.8 or unknown firmware: a public key is on file and matches.
	case publicKey
	/// Pre-2.8 or unknown firmware: no public key on file; direct messages use the channel key.
	case sharedKey
	/// Any version: the node's latest key does not match the stored one. Always shown.
	case keyMismatch

	/// The SF Symbol and color the row renders for this state.
	var glyph: (image: String, color: Color) {
		switch self {
		case .signed:
			return (SignedNodeIcon.symbolName, .green)
		case .notSigned:
			// An empty shield in gray: no identity verification, stated without alarm.
			return ("shield", .gray)
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
	static func status(firmwareVersion: String?, pkiEncrypted: Bool, keyMatch: Bool, signed: Bool) -> NodeSecurityIndicator {
		// A stored key that stopped matching is a warning regardless of firmware version.
		if pkiEncrypted && !keyMatch {
			return .keyMismatch
		}
		if supportsSigning(firmwareVersion: firmwareVersion) {
			return signed ? .signed : .notSigned
		}
		return pkiEncrypted ? .publicKey : .sharedKey
	}
}
