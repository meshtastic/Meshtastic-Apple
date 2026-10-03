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
	/// The mesh packet id. Only unique per sender, so uniqueness lives on `messageKey`
	/// (feature 021); replies and tapbacks still refer to messages by this id.
	var messageId: Int64 = 0
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

	// MARK: Multi-radio (feature 021)
	// Optional: rows stored before these existed have nil until the backfill reaches them, and
	// every reader must cope with that.

	/// Sender's node number, flat so queries don't join through `fromUser`.
	var fromNum: Int64?
	/// Recipient's node number (the broadcast address for channel messages).
	var toNum: Int64?
	/// Node number of the local radio this message belongs to: the radio that received it, or the
	/// one it was sent through. Scopes direct messages to the radio in the conversation.
	var localNodeNum: Int64?
	/// `ChannelIdentity` key of the channel, so channel messages group across radios whose slot
	/// indexes differ. Nil for direct messages.
	var channelKey: String?
	/// `"\(fromNum):\(messageId)"`: a packet id is only unique per sender. Set on every insert
	/// (ingest and send), so a sent message and its mesh echo merge on it. Nil on rows the
	/// backfill hasn't reached yet; SQLite allows any number of NULLs under the unique index.
	@Attribute(.unique) var messageKey: String?
	/// A `SystemEvent` raw value. 0 is a real message; anything else is a row the app wrote into a
	/// conversation itself, never sent or received (T377).
	var systemEvent: Int32 = 0
	/// For a `.channelChanged` row: the channel's key before the change. `channelKey` is the key
	/// after it.
	var previousChannelKey: String?

	var fromUser: UserEntity?
	var toUser: UserEntity?

	init() {}

	static func key(fromNum: Int64, messageId: Int64) -> String {
		"\(fromNum):\(messageId)"
	}

	/// Rows the app writes into a conversation itself (T377).
	enum SystemEvent: Int32 {
		/// One of the user's radios moved a channel slot to a different channel: another preset,
		/// name, key or mesh. Shown in that radio's thread between the history before and after.
		case channelChanged = 1
	}

	/// True for a row the app wrote itself rather than a message sent or received.
	var isSystemEvent: Bool { systemEvent != 0 }
}

extension MessageEntity {
	/// Drops later occurrences of a repeated `messageId`, preserving order.
	///
	/// Uniqueness (`messageKey`) is enforced per save:
	/// a sent message (main context) and its mesh echo (ingest actor) can coexist
	/// briefly before the constraint merges them. Two senders can also pick the same
	/// packet id now that `messageId` itself isn't unique (rare: 32-bit random ids).
	/// The message lists key their
	/// `ForEach` on `messageId`, and handing SwiftUI duplicate ids corrupts the
	/// List's collection-view batch update, which crashes. First occurrence wins —
	/// in the lists' chronological order that is the row the user already sees.
	static func deduplicatedByMessageId(_ messages: [MessageEntity]) -> [MessageEntity] {
		var seen = Set<Int64>()
		seen.reserveCapacity(messages.count)
		return messages.filter { seen.insert($0.messageId).inserted }
	}
}
