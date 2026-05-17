//
//  ChannelEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/22.
//
import Foundation
import SwiftData
import MeshtasticProtobufs

extension ChannelEntity {
	@MainActor
	var allPrivateMessages: [MessageEntity] {
		let context = PersistenceController.shared.context
		let channelIndex = self.index
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.toUser == nil && msg.isEmoji == false
			},
			sortBy: [SortDescriptor(\.messageTimestamp, order: .forward)]
		)
		return (try? context.fetch(descriptor)) ?? []
	}

	@MainActor
	var mostRecentPrivateMessage: MessageEntity? {
		let context = PersistenceController.shared.context
		let channelIndex = self.index
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.toUser == nil && msg.isEmoji == false
			},
			sortBy: [SortDescriptor(\.messageTimestamp, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? context.fetch(descriptor).first
	}

	@MainActor
	func unreadMessages(context: ModelContext) -> Int {
		let channelIndex = self.index
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.toUser == nil && msg.isEmoji == false && msg.read == false
			}
		)
		return (try? context.fetchCount(descriptor)) ?? 0
	}

	@MainActor
	var unreadMessages: Int { unreadMessages(context: PersistenceController.shared.context) }

	var protoBuf: Channel {
		var channel = Channel()
		channel.index = self.index
		channel.settings.name = self.name ?? ""
		channel.settings.psk = self.psk ?? Data()
		channel.role = Channel.Role(rawValue: Int(self.role)) ?? Channel.Role.secondary
		channel.settings.moduleSettings.positionPrecision = UInt32(self.positionPrecision)
		channel.settings.moduleSettings.isMuted = self.mute
		return channel
	}
}
