// UserEntityPublicKeyTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

/// Covers `UserEntity.applyInboundPublicKey(_:nodeNum:)` — the first-wins public-key handling shared
/// by the three inbound ingestion paths (UpdateSwiftData NodeInfo + User, MeshPackets NodeInfo).
@Suite("UserEntity.applyInboundPublicKey")
@MainActor
struct UserEntityApplyInboundPublicKeyTests {

	private let keyA = Data([0x01, 0x02, 0x03, 0x04])
	private let keyB = Data([0xAA, 0xBB, 0xCC, 0xDD])

	@Test("stores the first non-empty key when none is on file")
	func storesFirstKey() {
		let user = UserEntity()
		let outcome = user.applyInboundPublicKey(keyA, nodeNum: 42)

		#expect(outcome == .stored)
		#expect(user.publicKey == keyA)
		#expect(user.pkiEncrypted == true)
		#expect(user.keyMatch == true)          // untouched — no mismatch
		#expect(user.newPublicKey == nil)
	}

	@Test("treats a non-nil but empty stored key as no key and stores")
	func emptyStoredKeyIsTreatedAsNoKey() {
		let user = UserEntity()
		user.publicKey = Data()                 // non-nil but empty — must NOT count as a stored key
		let outcome = user.applyInboundPublicKey(keyA, nodeNum: 42)

		#expect(outcome == .stored)
		#expect(user.publicKey == keyA)
	}

	@Test("ignores an empty inbound key")
	func ignoresEmptyInboundKey() {
		let user = UserEntity()
		user.publicKey = keyA
		user.pkiEncrypted = true
		let outcome = user.applyInboundPublicKey(Data(), nodeNum: 42)

		#expect(outcome == .ignoredEmpty)
		#expect(user.publicKey == keyA)         // unchanged
		#expect(user.keyMatch == true)
	}

	@Test("a matching inbound key is a no-op")
	func matchingKeyIsNoOp() {
		let user = UserEntity()
		user.publicKey = keyA
		user.pkiEncrypted = true
		let outcome = user.applyInboundPublicKey(keyA, nodeNum: 42)

		#expect(outcome == .matched)
		#expect(user.publicKey == keyA)
		#expect(user.keyMatch == true)
		#expect(user.newPublicKey == nil)
	}

	@Test("a different inbound key is refused and surfaced to the UI (key-substitution attempt)")
	func mismatchKeepsStoredKeyAndFlagsUI() {
		let user = UserEntity()
		user.publicKey = keyA
		user.pkiEncrypted = true
		let outcome = user.applyInboundPublicKey(keyB, nodeNum: 42)

		#expect(outcome == .mismatch)
		#expect(user.publicKey == keyA)         // first-wins: stored key stands
		#expect(user.keyMatch == false)         // drives the red key.slash indicator
		#expect(user.newPublicKey == keyB)      // records the rejected key
	}
}
