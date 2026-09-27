//
//  ChannelMessageQuery.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import SwiftData

/// Queries for one channel's timeline (feature 021, T083/T084).
///
/// A channel's slot number is only meaningful on one radio: two radios can hold the same channel
/// in different slots, or different channels in the same slot. With more than one radio
/// (`multiRadio`) and a known `channelKey`, the timeline is every message with that key, plus this
/// radio's messages in this slot (which covers rows from before the channel was renamed or rekeyed,
/// and rows the backfill hasn't reached). Without a key yet, it's this radio's messages in this
/// slot. With one radio it's the single-radio query by slot, as before.
struct ChannelMessageQuery {
	let channelIndex: Int32
	let channelKey: String?
	/// The radio whose channel list this channel is from.
	let radioNum: Int64
	let multiRadio: Bool

	/// The channel's messages, or only its unread ones.
	func messages(unreadOnly: Bool = false) -> Predicate<MessageEntity> {
		let channelIndex = channelIndex
		let radioNum = radioNum
		guard multiRadio else {
			return #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.isEmoji == false
				&& (!unreadOnly || $0.read == false)
			}
		}
		guard let key = channelKey else {
			return #Predicate<MessageEntity> {
				$0.channel == channelIndex && ($0.localNodeNum ?? radioNum) == radioNum
				&& $0.toUser == nil && $0.isEmoji == false && (!unreadOnly || $0.read == false)
			}
		}
		// Composed from parts: as one expression it's too much for the type checker.
		let base = #Predicate<MessageEntity> {
			$0.toUser == nil && $0.isEmoji == false && (!unreadOnly || $0.read == false)
		}
		let byKey = #Predicate<MessageEntity> { $0.channelKey == key }
		let bySlot = #Predicate<MessageEntity> {
			$0.channel == channelIndex && ($0.localNodeNum ?? radioNum) == radioNum
		}
		return #Predicate<MessageEntity> {
			base.evaluate($0) && (byKey.evaluate($0) || bySlot.evaluate($0))
		}
	}

	/// Reactions to `messageIDs`. Grouped by key, a reaction can arrive through another radio in
	/// another slot, so the slot isn't part of the match.
	func tapbacks(to messageIDs: [Int64]) -> Predicate<MessageEntity> {
		let channelIndex = channelIndex
		let radioNum = radioNum
		guard multiRadio else {
			return #Predicate<MessageEntity> { message in
				message.channel == channelIndex
				&& message.isEmoji == true
				&& messageIDs.contains(message.replyID)
			}
		}
		guard channelKey != nil else {
			return #Predicate<MessageEntity> { message in
				message.channel == channelIndex
				&& (message.localNodeNum ?? radioNum) == radioNum
				&& message.isEmoji == true
				&& messageIDs.contains(message.replyID)
			}
		}
		return #Predicate<MessageEntity> { message in
			message.toUser == nil
			&& message.isEmoji == true
			&& messageIDs.contains(message.replyID)
		}
	}

	/// Unread messages on the channel, without the `toUser == nil` test, which the badge counts do
	/// in Swift (see `MyInfoEntity.unreadMessages` for why).
	func unreadCandidates() -> Predicate<MessageEntity> {
		let channelIndex = channelIndex
		let radioNum = radioNum
		guard multiRadio else {
			return #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && msg.isEmoji == false && msg.read == false
			}
		}
		guard let key = channelKey else {
			return #Predicate<MessageEntity> { msg in
				msg.channel == channelIndex && (msg.localNodeNum ?? radioNum) == radioNum
				&& msg.isEmoji == false && msg.read == false
			}
		}
		let base = #Predicate<MessageEntity> { $0.isEmoji == false && $0.read == false }
		let byKey = #Predicate<MessageEntity> { $0.channelKey == key }
		let bySlot = #Predicate<MessageEntity> {
			$0.channel == channelIndex && ($0.localNodeNum ?? radioNum) == radioNum
		}
		return #Predicate<MessageEntity> {
			base.evaluate($0) && (byKey.evaluate($0) || bySlot.evaluate($0))
		}
	}

	/// True when the store knows more than one of the user's radios.
	static func isMultiRadio(in context: ModelContext) -> Bool {
		((try? context.fetchCount(FetchDescriptor<MyInfoEntity>())) ?? 0) > 1
	}

	/// Newest first, then by id.
	static func fetch(_ predicate: Predicate<MessageEntity>, limit: Int?, in context: ModelContext) throws -> [MessageEntity] {
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: predicate,
			sortBy: [
				SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse),
				SortDescriptor(\MessageEntity.messageId, order: .reverse)
			]
		)
		if let limit {
			descriptor.fetchLimit = limit
		}
		return try context.fetch(descriptor)
	}

	/// Of `radios` (in order), the ones that have the channel `key`, each with its slot for it.
	static func slots(for key: String, among radios: [Int64], in context: ModelContext) -> [ChannelSlot] {
		radios.compactMap { radio in
			let keys = (try? MultiRadioBackfill.channelKeysByIndex(for: radio, in: context, updateStored: false)) ?? [:]
			guard let index = keys.filter({ $0.value == key }).keys.min() else { return nil }
			return ChannelSlot(radio: radio, index: index)
		}
	}
}

/// One radio's slot for a channel.
struct ChannelSlot: Hashable {
	let radio: Int64
	let index: Int32
}
