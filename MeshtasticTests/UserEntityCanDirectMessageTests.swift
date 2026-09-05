//
//  UserEntityCanDirectMessageTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/5/26.
//

import Testing
import Foundation
@testable import Meshtastic

/// Covers `UserEntity.canDirectMessage` — the gate behind the Message button in NodeDetail and the
/// node list. Both signals have to pass: the node has to accept messages, and we need a public key
/// for it or the sending radio refuses with `PKI_SEND_FAIL_PUBLIC_KEY`.
@Suite("UserEntity.canDirectMessage")
@MainActor
struct UserEntityCanDirectMessageTests {

	private let key = Data(repeating: 0x2B, count: 32)

	private func user(key: Data?, unmessagable: Bool) -> UserEntity {
		let user = UserEntity()
		user.publicKey = key
		user.unmessagable = unmessagable
		return user
	}

	@Test("allows a messagable node with a key")
	func allowsKeyedMessagableNode() {
		#expect(user(key: key, unmessagable: false).canDirectMessage)
	}

	@Test("blocks a node that has no key on file")
	func blocksNodeWithoutKey() {
		#expect(!user(key: nil, unmessagable: false).canDirectMessage)
	}

	@Test("blocks a node whose stored key is empty rather than nil")
	func blocksNodeWithEmptyKey() {
		// Heard-but-never-introduced neighbors can land with a non-nil empty key; an empty key is
		// no key as far as the radio is concerned.
		#expect(!user(key: Data(), unmessagable: false).canDirectMessage)
	}

	@Test("blocks an unmessagable node even when a key is on file")
	func blocksUnmessagableNode() {
		#expect(!user(key: key, unmessagable: true).canDirectMessage)
	}

	@Test("blocks a node that is unmessagable and keyless")
	func blocksUnmessagableKeylessNode() {
		#expect(!user(key: nil, unmessagable: true).canDirectMessage)
	}

	@Test("still offers the Message shortcut when a thread already exists")
	func keepsShortcutForExistingThread() {
		let contact = user(key: nil, unmessagable: true)
		contact.lastMessage = Date()

		#expect(!contact.canDirectMessage)          // sending is still refused
		#expect(contact.showsDirectMessageAction)   // but the thread stays reachable
	}

	@Test("hides the Message shortcut when there is no thread to open")
	func hidesShortcutWithoutThread() {
		#expect(!user(key: nil, unmessagable: false).showsDirectMessageAction)
	}

	@Test("offers the Message shortcut for a contact we can message")
	func offersShortcutForMessagableContact() {
		#expect(user(key: key, unmessagable: false).showsDirectMessageAction)
	}
}
