//
//  MyInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
@preconcurrency import SwiftData

extension MyInfoEntity {
	@MainActor
	var messageList: [MessageEntity] {
		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.isEmoji == false
			},
			sortBy: [SortDescriptor(\MessageEntity.messageTimestamp, order: .forward)]
		)
		let messages = (try? context.fetch(descriptor)) ?? []
		return messages.filter { $0.toUser == nil }
	}

	@MainActor
	func unreadMessages(context: ModelContext) -> Int {
		// Count via SQL rather than materializing every unread message and filtering in
		// Swift — this is called per incoming channel message, so the old fetch-all-then-
		// filter was O(unread) per message (quadratic over a burst) and stalled slower
		// devices under heavy traffic. toUser == nil selects channel (non-DM) messages.
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.isEmoji == false && msg.read == false && msg.toUser == nil
			}
		)
		return (try? context.fetchCount(descriptor)) ?? 0
	}

	@MainActor
	var unreadMessages: Int { unreadMessages(context: PersistenceController.shared.context) }

	var hasAdmin: Bool {
		let adminChannel = channels.filter { $0.name?.lowercased() == "admin" }
		return adminChannel.count > 0
	}
}
