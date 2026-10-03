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
		// Fetch a small batch and find the first channel message in Swift. A channel-change row
		// isn't a message, so it's never the preview (T377).
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.isEmoji == false && msg.systemEvent == 0
			},
			sortBy: [SortDescriptor(\.messageTimestamp, order: .reverse)]
		)
		descriptor.fetchLimit = 10
		let batch = (try? context.fetch(descriptor)) ?? []
		return batch.first { $0.toUser == nil }
	}

	/// The query for this channel's timeline. Feature 021: with more than one radio, the
	/// channel's messages are grouped by its key, following the slot's history on its radio
	/// (T378); with one, it's the slot query it always was.
	@MainActor
	func messageQuery(context: ModelContext) -> ChannelMessageQuery {
		ChannelMessageQuery.make(
			channelIndex: self.index,
			channelKey: self.channelKey,
			radioNum: self.myInfoChannel?.myNodeNum ?? 0,
			multiRadio: ChannelMessageQuery.isMultiRadio(in: context),
			in: context
		)
	}

	/// True when deleting this channel's conversation also removes messages another of the
	/// user's radios shows: some stretch of its history is a channel another radio has now, or
	/// had earlier (that radio's change rows, V22-3).
	@MainActor
	func sharesMessagesWithOtherRadios(context: ModelContext) -> Bool {
		let query = messageQuery(context: context)
		guard query.multiRadio, let key = query.channelKey else { return false }
		let historyKeys = Set(query.segments.isEmpty ? [key] : query.segments.map(\.key))
		let radio = query.radioNum
		let channels = (try? context.fetch(FetchDescriptor<ChannelEntity>())) ?? []
		let sharedNow = channels.contains { channel in
			guard let other = channel.myInfoChannel?.myNodeNum, other != radio,
				  let otherKey = channel.channelKey else { return false }
			return historyKeys.contains(otherKey)
		}
		if sharedNow { return true }
		// Change rows are few; the radio test runs in Swift (an optional `!=` in a predicate
		// also matches rows without a radio).
		let eventRaw = MessageEntity.SystemEvent.channelChanged.rawValue
		let events = (try? context.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.systemEvent == eventRaw }))) ?? []
		return events.contains { event in
			guard let other = event.localNodeNum, other != radio else { return false }
			return [event.channelKey, event.previousChannelKey].contains { $0.map(historyKeys.contains) ?? false }
		}
	}

	@MainActor
	func unreadMessages(context: ModelContext) -> Int {
		let query = messageQuery(context: context)
		let descriptor = FetchDescriptor<MessageEntity>(predicate: query.unreadCandidates())
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

	/// Channel names reserved for module traffic (legacy remote admin, GPIO, serial, MQTT).
	/// Channels with these names carry module protocol data, so the Messages channel list
	/// hides them and the channel editor warns when one is entered.
	static let reservedModuleNames = ["admin", "gpio", "serial", "mqtt"]

	static func isReservedModuleName(_ name: String) -> Bool {
		reservedModuleNames.contains(name.lowercased())
	}
}
