//
//  ChannelEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/22.
//
import Foundation
import CoreData
import MeshtasticProtobufs

extension ChannelEntity {
	var messagePredicate: NSPredicate {
		return NSPredicate(format: "channel == %ld AND toUser == nil AND isEmoji == false", self.index)
	}

	var messageFetchRequest: NSFetchRequest<MessageEntity> {
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: true)]
		fetchRequest.predicate = messagePredicate
		return fetchRequest
	}

	var allPrivateMessages: [MessageEntity] {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = messageFetchRequest

		return (try? context.fetch(fetchRequest)) ?? [MessageEntity]()
	}

	var mostRecentPrivateMessage: MessageEntity? {
		// Most recent channel message (descending, limit 1)
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = messageFetchRequest
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: false)]
		fetchRequest.fetchLimit = 1

		return (try? context.fetch(fetchRequest))?.first
	}

	func unreadMessages(context: NSManagedObjectContext) -> Int {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = messageFetchRequest
		fetchRequest.sortDescriptors = [] // sort is irrelvant.
		fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [fetchRequest.predicate!, NSPredicate(format: "read == false")])

		return (try? context.count(for: fetchRequest)) ?? 0
	}

	// Backwards-compatible property (uses viewContext)
	var unreadMessages: Int { unreadMessages(context: PersistenceController.shared.container.viewContext) }

	var protoBuf: Channel {
		var channel = Channel()
		channel.index = self.index
		channel.settings.name = self.name ?? ""
		channel.settings.psk = self.psk ?? Data()
		channel.role = Channel.Role(rawValue: Int(self.role)) ?? Channel.Role.secondary
		channel.settings.moduleSettings.positionPrecision = UInt32(self.positionPrecision)
		channel.settings.moduleSettings.isClientMuted = self.mute
		return channel
	}
}
