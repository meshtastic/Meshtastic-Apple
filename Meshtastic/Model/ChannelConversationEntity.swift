//
//  ChannelConversationEntity.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
import SwiftData

/// Which channel the broadcast messages stored under one `MessageEntity.channel` value belong to.
///
/// A key of 0 or more is a radio slot: it records the channel whose messages that slot holds, so
/// the next time the channel set changes the app can tell a moved channel from a replaced one. A
/// negative key is an archived conversation, for a channel that has left the radio; its messages
/// are stored under that key and come back to a slot if the channel returns.
///
/// `token` is a one way digest of the channel's effective name and key, so this table never holds
/// a PSK.
@Model
final class ChannelConversationEntity {
	var key: Int32 = 0
	var token: String = ""
	var name: String = ""
	var archivedAt: Date?

	init(key: Int32, token: String, name: String, archivedAt: Date? = nil) {
		self.key = key
		self.token = token
		self.name = name
		self.archivedAt = archivedAt
	}

	var isArchived: Bool { key < 0 }
}
