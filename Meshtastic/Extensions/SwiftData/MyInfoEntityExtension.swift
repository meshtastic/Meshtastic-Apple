//
//  MyInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
import SwiftData

extension MyInfoEntity {
	@MainActor
	var messageList: [MessageEntity] {
		let context = PersistenceController.shared.context
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.toUser == nil && msg.isEmoji == false
			},
			sortBy: [SortDescriptor(\MessageEntity.messageTimestamp, order: .forward)]
		)
		return (try? context.fetch(descriptor)) ?? []
	}

	@MainActor
	func unreadMessages(context: ModelContext) -> Int {
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.toUser == nil && msg.isEmoji == false && msg.read == false
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
