//
//  MessageEntity.swift
//  Meshtastic
//
//  SwiftData model for messages.
//

import Foundation
import SwiftData

@Model
final class MessageEntity {
	var ackError: Int32 = 0
	var ackSNR: Float = 0.0
	var ackTimestamp: Int32 = 0
	var admin: Bool = false
	var adminDescription: String?
	var channel: Int32 = 0
	var isEmoji: Bool = false
	@Attribute(.unique) var messageId: Int64 = 0
	var messagePayload: String? = ""
	var messagePayloadMarkdown: String?
	var messagePayloadTranslated: String?
	var messagePayloadTranslatedMarkdown: String?
	var messageTimestamp: Int32 = 0
	var pkiEncrypted: Bool = false
	var portNum: Int32 = 0
	var publicKey: Data?
	var read: Bool = false
	var realACK: Bool = false
	var receivedACK: Bool = false
	var relayNode: Int64 = 0
	var relays: Int16 = 0
	var replyID: Int64 = 0
	var rssi: Int32 = 0
	var showTranslatedMessage: Bool = false
	var snr: Float = 0.0
	/// True when the radio verified this received broadcast's XEdDSA signature (MeshPacket.xeddsa_signed, field 22).
	/// Firmware only ever sets this on broadcasts — never on DMs — so it can be trusted on its own.
	var xeddsaSigned: Bool = false

	var fromUser: UserEntity?
	var toUser: UserEntity?

	init() {}
}

extension MessageEntity {
	/// Drops later occurrences of a repeated `messageId`, preserving order.
	///
	/// `messageId` is `@Attribute(.unique)`, but uniqueness is enforced per save:
	/// a sent message (main context) and its mesh echo (ingest actor) can coexist
	/// briefly before the constraint merges them. The message lists key their
	/// `ForEach` on `messageId`, and handing SwiftUI duplicate ids corrupts the
	/// List's collection-view batch update, which crashes. First occurrence wins —
	/// in the lists' chronological order that is the row the user already sees.
	static func deduplicatedByMessageId(_ messages: [MessageEntity]) -> [MessageEntity] {
		var seen = Set<Int64>()
		seen.reserveCapacity(messages.count)
		return messages.filter { seen.insert($0.messageId).inserted }
	}
}
