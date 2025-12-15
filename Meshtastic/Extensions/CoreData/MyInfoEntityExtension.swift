//
//  MyInfoEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/3/23.
//

import Foundation
import CoreData

extension MyInfoEntity {
	var messagePredicate: NSPredicate {
		return NSPredicate(format: "toUser == nil AND isEmoji == false")
	}

	var messageFetchRequest: NSFetchRequest<MessageEntity> {
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: true)]
		fetchRequest.predicate = messagePredicate
		return fetchRequest
	}

	var messageList: [MessageEntity] {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = messageFetchRequest

		return (try? context.fetch(messageFetchRequest)) ?? [MessageEntity]()
	}

	func unreadMessages(context: NSManagedObjectContext) -> Int {
		// Returns the count of unread *channel* messages
		let fetchRequest = messageFetchRequest
		fetchRequest.sortDescriptors = [] // sort is irrelevant.
		fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [fetchRequest.predicate!, NSPredicate(format: "read == false")])

		return (try? context.count(for: fetchRequest)) ?? 0
	}

	// Backwards-compatible property (uses viewContext)
	var unreadMessages: Int { unreadMessages(context: PersistenceController.shared.container.viewContext) }

	var hasAdmin: Bool {
		let adminChannel = channels?.filter { ($0 as AnyObject).name?.lowercased() == "admin" }
		return adminChannel?.count ?? 0 > 0
	}
}
