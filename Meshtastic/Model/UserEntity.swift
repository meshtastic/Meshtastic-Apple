//
//  UserEntity.swift
//  Meshtastic
//
//  SwiftData model for user information.
//

import Foundation
import OSLog
import SwiftData

@Model
final class UserEntity {
	var hwDisplayName: String?
	var hwModel: String?
	var hwModelId: Int32 = 0
	var isLicensed: Bool = false
	var keyMatch: Bool = true
	var lastMessage: Date?
	var longName: String?
	var mute: Bool = false
	var newPublicKey: Data?
	@Attribute(.unique) var num: Int64 = 0
	var numString: String?
	var pkiEncrypted: Bool = false
	var publicKey: Data?
	var role: Int32 = 0
	var shortName: String?
	var unmessagable: Bool = false
	var userId: String?

	@Relationship(inverse: \MessageEntity.fromUser)
	var sentMessages: [MessageEntity] = []

	@Relationship(inverse: \MessageEntity.toUser)
	var receivedMessages: [MessageEntity] = []

	var userNode: NodeInfoEntity?

	init() {}
}

// MARK: - First-wins public-key handling

extension UserEntity {

	/// The result of applying an inbound public key to this user via `applyInboundPublicKey(_:nodeNum:)`.
	enum PublicKeyUpdateOutcome: Equatable {
		/// The inbound key was empty — nothing to apply.
		case ignoredEmpty
		/// No key was on file yet, so the inbound key was stored (and `pkiEncrypted` set).
		case stored
		/// The inbound key matched the stored key — no change.
		case matched
		/// A *different* key arrived for a contact that already has one. The stored key is kept
		/// (first-wins); `keyMatch` is cleared and `newPublicKey` records the rejected key so the UI
		/// trust indicators surface the possible key-substitution attempt.
		case mismatch
	}

	/// Applies **first-wins** semantics for an inbound public key.
	///
	/// Once a non-empty key is stored for a contact it is never silently overwritten by a different
	/// inbound key — that would let any mesh/MQTT peer substitute a trusted contact's key and MITM the
	/// victim's PKC direct messages. A differing key is refused and surfaced to the UI (`keyMatch =
	/// false`, `newPublicKey = inbound`) rather than only logged; the stored key stands.
	///
	/// - Parameters:
	///   - inboundKey: The public key carried by the inbound NodeInfo/User protobuf.
	///   - nodeNum: The node number, used only for the security log line on a mismatch.
	/// - Returns: The outcome, primarily for tests and callers that want to react to a mismatch.
	@discardableResult
	func applyInboundPublicKey(_ inboundKey: Data, nodeNum: Int64) -> PublicKeyUpdateOutcome {
		guard !inboundKey.isEmpty else { return .ignoredEmpty }

		if let storedKey = publicKey, !storedKey.isEmpty {
			guard storedKey != inboundKey else { return .matched }
			keyMatch = false
			newPublicKey = inboundKey
			Logger.data.error("🔐 [Security] Ignoring inbound public key change for node \(nodeNum, privacy: .public); a different key is already stored (possible key-substitution attempt).")
			return .mismatch
		}

		pkiEncrypted = true
		publicKey = inboundKey
		return .stored
	}
}
