//
//  SharedContactKeyGuard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Foundation
import MeshtasticProtobufs

extension SharedContact {
	/// Whether this contact carries a public key.
	///
	/// Firmware applies an `add_contact` through `CopyUserToNodeInfoLite`, which assigns
	/// `public_key` unconditionally. A contact with no key therefore erases the key the radio
	/// already holds for that node, and the next direct message to it fails with
	/// `PKI_SEND_FAIL_PUBLIC_KEY` instead of falling back to channel encryption. Nothing we send
	/// to the radio should be able to do that, so contacts without a key are refused.
	var carriesPublicKey: Bool {
		!user.publicKey.isEmpty
	}
}
