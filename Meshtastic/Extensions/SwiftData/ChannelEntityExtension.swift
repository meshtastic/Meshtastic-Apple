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

/// Deduped, index-sorted channels for `node`'s synced config — one entry per channel index (config sync can
/// produce transient duplicate rows for the same index before settling). Shared by the Channels settings
/// screen and the waypoint recipient picker so their channel lists never drift apart.
func dedupedChannels(for node: NodeInfoEntity?) -> [ChannelEntity] {
	guard let channels = node?.myInfo?.channels else { return [] }
	var byIndex: [Int32: ChannelEntity] = [:]
	for channel in channels {
		byIndex[channel.index] = channel
	}
	return byIndex.values.sorted { $0.index < $1.index }
}

/// The channel treated as "primary" for display purposes: index 0, or explicitly marked role 1 — firmware
/// can reassign which channel is primary without it being index 0.
func primaryChannel(in channels: [ChannelEntity]) -> ChannelEntity? {
	channels.first(where: { $0.index == 0 || $0.role == 1 })
}

/// Display name for the primary channel: its configured name if set, else "Custom" for a non-preset LoRa
/// config, else the modem-preset's Android channel name (e.g. "LongFast"), falling back to "LongFast" if the
/// preset can't be resolved (matching the Channels settings screen), or a generic "Broadcast" only when
/// `node` itself is unavailable (e.g. the waypoint picker while disconnected — a case the Channels screen,
/// which always has a node, never hits).
func channelDisplayName(channels: [ChannelEntity], node: NodeInfoEntity?) -> String {
	if let primary = primaryChannel(in: channels), let name = primary.name, !name.isEmpty {
		return name
	}
	guard let node else { return "Broadcast".localized }
	if node.loRaConfig?.usePreset == false {
		return "Custom".localized
	}
	guard let preset = ModemPresets(rawValue: Int(node.loRaConfig?.modemPreset ?? 0)) else {
		return "LongFast"
	}
	return preset.androidChannelName
}
