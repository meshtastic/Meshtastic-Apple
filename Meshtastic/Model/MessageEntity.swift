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

	var fromUser: UserEntity?
	var toUser: UserEntity?

	init() {}
}
