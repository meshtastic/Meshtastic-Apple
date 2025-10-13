//
//  MyInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
import CoreData

extension MyInfoEntity {

	var messageList: [MessageEntity] {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: true)]
		fetchRequest.predicate = NSPredicate(format: "toUser == nil")

		return (try? context.fetch(fetchRequest)) ?? [MessageEntity]()
	}

	func unreadMessages(context: NSManagedObjectContext) -> Int {
		// Returns the count of unread *channel* messages
		let fetchRequest = MessageEntity.fetchRequest()
		// sort is irrelvant.
		fetchRequest.predicate = NSPredicate(format: "toUser == nil AND isEmoji == false AND read == false")
		return (try? context.count(for: fetchRequest)) ?? 0
	}

	// Backwards-compatible property (uses viewContext)
	var unreadMessages: Int { unreadMessages(context: PersistenceController.shared.container.viewContext) }

	var hasAdmin: Bool {
		let adminChannel = channels?.filter { ($0 as AnyObject).name?.lowercased() == "admin" }
		return adminChannel?.count ?? 0 > 0
	}
}
