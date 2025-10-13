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

	var allPrivateMessages: [MessageEntity] {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: true)]
		fetchRequest.predicate = NSPredicate(format: "channel == %ld AND toUser == nil AND isEmoji == false", self.index)

		return (try? context.fetch(fetchRequest)) ?? [MessageEntity]()
	}

	var mostRecentPrivateMessage: MessageEntity? {
		// Most recent channel message (descending, limit 1)
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "messageTimestamp", ascending: false)]
		fetchRequest.predicate = NSPredicate(format: "channel == %ld AND toUser == nil AND isEmoji == false", self.index)
		fetchRequest.fetchLimit = 1

		return (try? context.fetch(fetchRequest))?.first
	}

	func unreadMessages(context: NSManagedObjectContext) -> Int {
		let context = PersistenceController.shared.container.viewContext
		let fetchRequest = MessageEntity.fetchRequest()
		// sort is irrelvant.
		fetchRequest.predicate = NSPredicate(format: "channel == %ld AND toUser == nil AND isEmoji == false AND read == false", self.index)
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
