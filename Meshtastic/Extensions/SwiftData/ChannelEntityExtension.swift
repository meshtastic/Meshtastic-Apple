//
//  ChannelEntityExtension.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/22.
//
import Foundation
@preconcurrency import SwiftData
import MeshtasticProtobufs

extension ChannelEntity {
	@MainActor
	var allPrivateMessages: [MessageEntity] {
		let context = PersistenceController.shared.context
		let channelIndex = self.index
		// NOTE: toUser == nil is intentionally absent from the predicate — comparing an optional
		// relationship to nil in a #Predicate crashes SwiftData on iOS 26. Filter in Swift instead.
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.isEmoji == false
			},
			sortBy: [SortDescriptor(\.messageTimestamp, order: .forward)]
		)
		let messages = (try? context.fetch(descriptor)) ?? []
		return messages.filter { $0.toUser == nil }
	}

	@MainActor
	var mostRecentPrivateMessage: MessageEntity? {
		let context = PersistenceController.shared.context
		let channelIndex = self.index
		// Fetch a small batch and find the first channel message in Swift.
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.isEmoji == false
			},
			sortBy: [SortDescriptor(\.messageTimestamp, order: .reverse)]
		)
		descriptor.fetchLimit = 10
		let batch = (try? context.fetch(descriptor)) ?? []
		return batch.first { $0.toUser == nil }
	}

	@MainActor
	func unreadMessages(context: ModelContext) -> Int {
		let channelIndex = self.index
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.isEmoji == false && msg.read == false
			}
		)
		let messages = (try? context.fetch(descriptor)) ?? []
		return messages.filter { $0.toUser == nil }.count
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
