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
/// (`multiRadio`) and a known `channelKey`, the timeline is the slot's history on this radio
/// (T378): each channel the slot has had, for the time the slot had it (`segments`), with the
/// change rows between them, plus this radio's rows in the slot the backfill hasn't keyed yet.
/// Each segment is every message with that channel's key, whichever radio heard it. Without a key
/// yet, it's this radio's messages in this slot. With one radio it's the single-radio query by
/// slot, as before.
struct ChannelMessageQuery {
	let channelIndex: Int32
	let channelKey: String?
	/// The radio whose channel list this channel is from.
	let radioNum: Int64
	let multiRadio: Bool
	/// The slot's history on this radio, oldest first (`ChannelChangeEvents.segments`). Empty is
	/// one unbounded segment of `channelKey`.
	var segments: [ChannelChangeEvents.Segment] = []

	/// The query for `channelIndex` on `radioNum`, with the slot's history read from `context`.
	static func make(channelIndex: Int32, channelKey: String?, radioNum: Int64, multiRadio: Bool, in context: ModelContext) -> ChannelMessageQuery {
		var query = ChannelMessageQuery(channelIndex: channelIndex, channelKey: channelKey, radioNum: radioNum, multiRadio: multiRadio)
		if multiRadio, let channelKey {
			query.segments = ChannelChangeEvents.segments(radio: radioNum, slot: channelIndex, currentKey: channelKey, in: context)
		}
		return query
	}

	/// `segments`, or one unbounded segment of `key`.
	private func effectiveSegments(key: String) -> [ChannelChangeEvents.Segment] {
		segments.isEmpty ? [ChannelChangeEvents.Segment(key: key, start: nil, end: nil)] : segments
	}

	/// Real messages (not change rows) in any of `segments`, which mustn't be empty. Composed one
	/// segment at a time: as one expression it's too much for the type checker.
	///
	/// Another radio's rows count only within the segment's time bounds: that radio heard the
	/// channel, but this slot only had it for that stretch. `radio`'s own rows count whenever they
	/// were sent or received (V22-1): each carries the key its slot had when it was stored, and the
	/// radio delivers the packets it queued while the app was away after its settings, dated
	/// before the change row that the settings produced.
	private static func inSegments(_ segments: [ChannelChangeEvents.Segment], radio: Int64) -> Predicate<MessageEntity> {
		let ownRadio: Int64? = radio
		var combined: Predicate<MessageEntity>?
		for segment in segments {
			let key: String? = segment.key
			// A row still keyed in the old format belongs to the same channel until it's converted.
			let legacy: String? = segment.legacyKey ?? segment.key
			let start = segment.start ?? Int32.min
			let end = segment.end ?? Int32.max
			let unboundedEnd = segment.end == nil
			let inBounds = #Predicate<MessageEntity> {
				$0.localNodeNum == ownRadio
				|| ($0.messageTimestamp >= start && (unboundedEnd || $0.messageTimestamp < end))
			}
			let this = #Predicate<MessageEntity> {
				($0.channelKey == key || $0.channelKey == legacy) && inBounds.evaluate($0)
			}
			if let previous = combined {
				combined = #Predicate<MessageEntity> { previous.evaluate($0) || this.evaluate($0) }
			} else {
				combined = this
			}
		}
		let noEvent = #Predicate<MessageEntity> { $0.systemEvent == 0 }
		guard let anySegment = combined else { return noEvent }
		return #Predicate<MessageEntity> { noEvent.evaluate($0) && anySegment.evaluate($0) }
	}

	/// This radio's change rows for the slot.
	private func ownEvents() -> Predicate<MessageEntity> {
		let channelIndex = channelIndex
		let radio: Int64? = radioNum
		let eventRaw = MessageEntity.SystemEvent.channelChanged.rawValue
		return #Predicate<MessageEntity> {
			$0.systemEvent == eventRaw && $0.localNodeNum == radio && $0.channel == channelIndex
		}
	}

	/// This radio's rows in the slot that have no key yet (the backfill hasn't reached them).
	private func unkeyedInSlot() -> Predicate<MessageEntity> {
		let channelIndex = channelIndex
		let radioNum = radioNum
		return #Predicate<MessageEntity> {
			$0.channelKey == nil && $0.channel == channelIndex && ($0.localNodeNum ?? radioNum) == radioNum
		}
	}

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
		let bySegment = Self.inSegments(effectiveSegments(key: key), radio: radioNum)
		let unkeyed = unkeyedInSlot()
		let events = ownEvents()
		return #Predicate<MessageEntity> {
			base.evaluate($0) && (bySegment.evaluate($0) || unkeyed.evaluate($0) || events.evaluate($0))
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
		let bySegment = Self.inSegments(effectiveSegments(key: key), radio: radioNum)
		let unkeyed = unkeyedInSlot()
		return #Predicate<MessageEntity> {
			base.evaluate($0) && (bySegment.evaluate($0) || unkeyed.evaluate($0))
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
