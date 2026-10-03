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

/// Covers `SharedContact.comparedWithStoredKey` — what the add-contact sheet uses to tell the
/// person that importing is about to replace the key their node already holds for this contact.
@Suite("SharedContact.comparedWithStoredKey")
struct SharedContactStoredKeyComparisonTests {

	private let storedKey = Data(repeating: 0x2B, count: 32)
	private let otherKey = Data(repeating: 0x7F, count: 32)

	private func contact(key: Data) -> SharedContact {
		var user = User()
		user.id = "!47ea4b5a"
		user.longName = "Test Node"
		user.shortName = "test"
		user.publicKey = key

		var contact = SharedContact()
		contact.nodeNum = 1_206_537_050
		contact.user = user
		return contact
	}

	@Test("a node we hold no key for is establishing one")
	func noStoredKey() {
		#expect(contact(key: storedKey).comparedWithStoredKey(nil) == .establishesKey)
	}

	@Test("an empty stored key is the same as none")
	func emptyStoredKey() {
		// A node heard from but never identified has a row with no key on it.
		#expect(contact(key: storedKey).comparedWithStoredKey(Data()) == .establishesKey)
	}

	@Test("re-importing the same contact changes nothing")
	func sameKey() {
		#expect(contact(key: storedKey).comparedWithStoredKey(storedKey) == .matchesStoredKey)
	}

	@Test("a different key for a known contact is a replacement")
	func differentKey() {
		// The case the warning exists for: firmware's addFromContact applies this without
		// asking, and every later direct message is encrypted to the new key.
		#expect(contact(key: otherKey).comparedWithStoredKey(storedKey) == .replacesStoredKey)
	}

	@Test("a keyless contact against a stored key still reads as a replacement")
	func keylessContact() {
		// carriesPublicKey refuses this one before it reaches the radio, so the comparison only
		// has to avoid calling it a match — it must never report that nothing would change.
		var keyless = contact(key: storedKey)
		keyless.user.publicKey = Data()
		#expect(keyless.comparedWithStoredKey(storedKey) == .replacesStoredKey)
	}

	@Test("survives a serialize and decode round trip")
	func survivesRoundTrip() throws {
		// The sheet compares the contact decoded from the URL, not the one we built here.
		let encoded = try contact(key: otherKey).serializedData()
		let decoded = try SharedContact(serializedBytes: encoded)
		#expect(decoded.comparedWithStoredKey(storedKey) == .replacesStoredKey)
		#expect(decoded.comparedWithStoredKey(otherKey) == .matchesStoredKey)
	}
}

/// Covers what a *confirmed* key replacement does to the stored key. First-wins protects the
/// mesh path, but an `add_contact` has already given the radio the new key, so refusing it in the
/// app would leave the two disagreeing and flag a mismatch for a change the person asked for.
@Suite("Imported public key acceptance")
struct ImportedPublicKeyAcceptanceTests {

	private let storedKey = Data(repeating: 0x2B, count: 32)
	private let importedKey = Data(repeating: 0x7F, count: 32)

	@MainActor
	private func user(withKey key: Data) -> UserEntity {
		let context = TestContainerProvider.shared.mainContext
		let user = UserEntity()
		user.num = 1_206_537_050
		user.publicKey = key
		user.pkiEncrypted = true
		context.insert(user)
		return user
	}

	@Test("a confirmed import replaces the stored key and clears the mismatch")
	@MainActor
	func acceptsConfirmedReplacement() {
		let user = user(withKey: storedKey)
		// A mismatch recorded earlier by the mesh path is what the UI shows as a key warning.
		user.keyMatch = false
		user.newPublicKey = importedKey

		user.acceptImportedPublicKey(importedKey)

		#expect(user.publicKey == importedKey)
		#expect(user.keyMatch)
		#expect(user.newPublicKey == nil)
	}

	@Test("an unconfirmed inbound key is still refused")
	@MainActor
	func stillFirstWinsOnTheMeshPath() {
		let user = user(withKey: storedKey)
		#expect(user.applyInboundPublicKey(importedKey, nodeNum: 1) == .mismatch)
		#expect(user.publicKey == storedKey)
		#expect(!user.keyMatch)
	}

	@Test("a malformed key changes nothing")
	@MainActor
	func ignoresMalformedKey() {
		let user = user(withKey: storedKey)
		for bad in [Data(), Data(repeating: 0x01, count: 31), Data(repeating: 0x01, count: 33)] {
			user.acceptImportedPublicKey(bad)
			#expect(user.publicKey == storedKey)
		}
	}
}
