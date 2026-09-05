//
//  SharedContactKeyGuardTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Testing
import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

/// Covers `SharedContact.carriesPublicKey` — the guard that keeps a keyless contact from reaching
/// the radio, where it would overwrite the key already in the node db.
@Suite("SharedContact.carriesPublicKey")
struct SharedContactKeyGuardTests {

	private func contact(key: Data?) -> SharedContact {
		var user = User()
		user.id = "!47ea4b5a"
		user.longName = "Test Node"
		user.shortName = "test"
		if let key { user.publicKey = key }

		var contact = SharedContact()
		contact.nodeNum = 1_206_537_050
		contact.user = user
		return contact
	}

	@Test("accepts a contact carrying a full key")
	func acceptsFullKey() {
		#expect(contact(key: Data(repeating: 0x2B, count: 32)).carriesPublicKey)
	}

	@Test("refuses a contact whose key field was never set")
	func refusesUnsetKey() {
		#expect(!contact(key: nil).carriesPublicKey)
	}

	@Test("refuses a contact carrying an explicitly empty key")
	func refusesEmptyKey() {
		// This is what UserEntity.toProto() produces for a node we hold no key for, and what would
		// blank the radio's stored key if it were applied.
		#expect(!contact(key: Data()).carriesPublicKey)
	}

	@Test("survives a serialize and decode round trip")
	func survivesRoundTrip() throws {
		// addContactFromURL decodes from base64 before the guard runs, so the check has to hold on
		// the decoded value rather than the one we built.
		let encoded = try contact(key: Data()).serializedData()
		let decoded = try SharedContact(serializedBytes: encoded)
		#expect(!decoded.carriesPublicKey)

		let keyed = try contact(key: Data(repeating: 0x2B, count: 32)).serializedData()
		#expect(try SharedContact(serializedBytes: keyed).carriesPublicKey)
	}
}
