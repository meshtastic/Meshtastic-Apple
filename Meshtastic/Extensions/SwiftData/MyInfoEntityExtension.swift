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
		// NOTE: do NOT push `toUser == nil` into the #Predicate — comparing an optional
		// relationship to nil crashes SwiftData on iOS 26 (see AppState.refreshBadgeCount),
		// and on other OSes returns a wrong count (broke the channel badge). Fetch the
		// unread set and split in Swift. Callers must throttle this — it's O(unread).
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.isEmoji == false && msg.read == false
			}
		)
		let messages = (try? context.fetch(descriptor)) ?? []
		return messages.filter { $0.toUser == nil }.count
	}

	@MainActor
	var unreadMessages: Int { unreadMessages(context: PersistenceController.shared.context) }

	var hasAdmin: Bool {
		let adminChannel = channels.filter { $0.name?.lowercased() == "admin" }
		return adminChannel.count > 0
	}
}
