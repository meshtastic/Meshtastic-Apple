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
	// Well-formed Curve25519 public keys are exactly 32 bytes; the own-radio path insists on that.
	private let key32A = Data(repeating: 0x11, count: 32)
	private let key32B = Data(repeating: 0xAB, count: 32)

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

	@Test("the connected radio's own key replaces the stored one and clears a recorded mismatch")
	func ownRadioKeyIsGroundTruth() {
		let user = UserEntity()
		user.publicKey = key32A
		user.pkiEncrypted = true
		// A mesh packet already flagged the new key as a substitution attempt.
		user.keyMatch = false
		user.newPublicKey = key32B

		user.acceptOwnRadioPublicKey(key32B)

		#expect(user.publicKey == key32B)       // the radio's own report wins
		#expect(user.keyMatch == true)          // the mismatch flag clears
		#expect(user.newPublicKey == nil)
	}

	@Test("an empty key from the radio changes nothing, including a recorded mismatch")
	func ownRadioEmptyKeyIsIgnored() {
		let user = UserEntity()
		user.publicKey = key32A
		user.pkiEncrypted = true
		user.keyMatch = false
		user.newPublicKey = key32B

		user.acceptOwnRadioPublicKey(Data())

		#expect(user.publicKey == key32A)
		#expect(user.pkiEncrypted == true)
		#expect(user.keyMatch == false)         // an empty key must not clear a mismatch
		#expect(user.newPublicKey == key32B)
	}

	@Test("a malformed key from the radio changes nothing")
	func ownRadioMalformedKeyIsIgnored() {
		let user = UserEntity()
		user.publicKey = key32A
		user.pkiEncrypted = true
		user.keyMatch = false
		user.newPublicKey = key32B

		user.acceptOwnRadioPublicKey(keyB)      // 4 bytes, not a Curve25519 key

		#expect(user.publicKey == key32A)
		#expect(user.keyMatch == false)
		#expect(user.newPublicKey == key32B)
	}
}
