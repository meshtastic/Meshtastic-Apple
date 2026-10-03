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

	/// How this contact's key stands against the key already held for the same node.
	enum StoredKeyComparison: Equatable {
		/// No key on file for this node, so importing establishes one.
		case establishesKey
		/// The contact carries the key already stored — a re-import changes nothing.
		case matchesStoredKey
		/// A *different* key for a node we already hold one for. Importing replaces the stored
		/// key, and every later direct message is encrypted to the new one.
		case replacesStoredKey
	}

	/// Compares this contact's key with the one the radio already holds for the node.
	///
	/// `UserEntity.applyInboundPublicKey` gives keys arriving over the mesh first-wins
	/// treatment: a different key never silently replaces a stored one, because that is how a
	/// peer would substitute a contact's key and read their direct messages. An `add_contact`
	/// bypasses that entirely — firmware's `addFromContact` only refuses a key change for a node
	/// already marked manually verified, so for an ordinary contact the stored key is replaced
	/// without a word. An import is a deliberate act, so this is not refused the way an inbound
	/// key is; it is surfaced so the person doing it can see what it will do.
	///
	/// - Parameter storedKey: The key on file for this node, or nil when none is held.
	func comparedWithStoredKey(_ storedKey: Data?) -> StoredKeyComparison {
		guard let storedKey, !storedKey.isEmpty else { return .establishesKey }
		return storedKey == user.publicKey ? .matchesStoredKey : .replacesStoredKey
	}
}
