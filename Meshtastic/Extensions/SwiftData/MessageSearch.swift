//
//  MessageSearch.swift
//  Meshtastic
//
//  "Find in conversation" content search over the stored message text.
//
//  Scoped per-conversation (a channel, or a direct-message thread with one user), matching
//  Android's find-in-conversation UX. The search runs against the whole message store — not
//  the currently-loaded window — so messages that predate the current session are included.
//  Matching is case- and diacritic-insensitive substring (`localizedStandardContains`).
//

import Foundation
@preconcurrency import SwiftData

/// A lightweight, timeline-ordered handle to a search match. Carries the timestamp/id cursor so a
/// caller can both scroll to the match and work out how far back in the conversation it sits
/// (to expand a windowed message list until the match is loaded).
struct MessageSearchMatch: Equatable {
	let messageId: Int64
	let timestamp: Int32
}

/// Runs conversation content search on a background context so the (unindexed) `CONTAINS`
/// scan never blocks the main actor. Results are `MessageSearchMatch` value types, so they
/// cross the actor boundary safely. The context is read-only for search — it sees saved
/// messages (which is all the list displays anyway).
@ModelActor
actor MessageSearchActor {
	func channelMatches(channelIndex: Int32, query: String) throws -> [MessageSearchMatch] {
		try MessageSearch.channelMatches(in: modelContext, channelIndex: channelIndex, query: query)
	}

	func directMatches(userNum: Int64, query: String) throws -> [MessageSearchMatch] {
		try MessageSearch.directMatches(in: modelContext, userNum: userNum, query: query)
	}
}

enum MessageSearch {

	// MARK: Channel conversations

	/// Matches within a channel conversation, oldest → newest.
	// Note: `$0.toUser == nil` is a relationship-vs-nil comparison, which mis-counts / crashes
	// SwiftData only when used *bare* (see the warnings in MyInfoEntityExtension / ChannelEntityExtension).
	// It's safe here because a concrete scalar term leads the predicate (`channel == channelIndex`),
	// matching the shape ChannelMessageList already ships in its own fetches. Exercised on iOS 26 by
	// MessageSearchTests (empty and non-empty results), which keeps this shape honest.
	static func channelMatches(in context: ModelContext, channelIndex: Int32, query: String) throws -> [MessageSearchMatch] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return [] }
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.isEmoji == false
					&& ($0.messagePayload?.localizedStandardContains(trimmed) ?? false)
			},
			sortBy: [
				SortDescriptor(\MessageEntity.messageTimestamp, order: .forward),
				SortDescriptor(\MessageEntity.messageId, order: .forward)
			]
		)
		// Only the id/timestamp are needed to build matches — avoid hydrating message text + relationships.
		descriptor.propertiesToFetch = [\.messageId, \.messageTimestamp]
		return try context.fetch(descriptor).map { MessageSearchMatch(messageId: $0.messageId, timestamp: $0.messageTimestamp) }
	}

	/// Number of channel messages strictly newer than `match` in the timeline. Used to expand a
	/// windowed list (newest-first) until the match becomes visible: the match sits at rank
	/// `newerCount` from the newest message, so a window of `newerCount + 1` includes it.
	static func channelNewerCount(in context: ModelContext, channelIndex: Int32, than match: MessageSearchMatch) throws -> Int {
		let ts = match.timestamp
		let mid = match.messageId
		let newerByTimestamp = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.isEmoji == false && $0.messageTimestamp > ts
			}
		)
		let sameTimestampNewerId = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.isEmoji == false
					&& $0.messageTimestamp == ts && $0.messageId > mid
			}
		)
		return try context.fetchCount(newerByTimestamp) + context.fetchCount(sameTimestampNewerId)
	}

	// MARK: Direct-message conversations

	/// Matches within a direct-message thread with `userNum` (both incoming and outgoing),
	/// oldest → newest. Excludes emoji tapbacks, admin, and detection-sensor traffic to mirror the
	/// message list's own filtering.
	static func directMatches(in context: ModelContext, userNum: Int64, query: String) throws -> [MessageSearchMatch] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return [] }
		let detectionSensorPortNum: Int32 = 10
		// `toUser != nil` is safe for the same reason as the channel search: a concrete scalar term
		// (`fromUser?.num == userNum`) leads the predicate, mirroring fetchIncomingMessages' shipping shape.
		var incoming = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.fromUser?.num == userNum && $0.toUser != nil
					&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
					&& ($0.messagePayload?.localizedStandardContains(trimmed) ?? false)
			}
		)
		var outgoing = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.toUser?.num == userNum
					&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
					&& ($0.messagePayload?.localizedStandardContains(trimmed) ?? false)
			}
		)
		// Only the id/timestamp are needed to build matches — avoid hydrating message text + relationships.
		incoming.propertiesToFetch = [\.messageId, \.messageTimestamp]
		outgoing.propertiesToFetch = [\.messageId, \.messageTimestamp]
		let matches = try context.fetch(incoming) + context.fetch(outgoing)
		return matches
			.sorted {
				if $0.messageTimestamp == $1.messageTimestamp { return $0.messageId < $1.messageId }
				return $0.messageTimestamp < $1.messageTimestamp
			}
			.map { MessageSearchMatch(messageId: $0.messageId, timestamp: $0.messageTimestamp) }
	}

	/// Number of direct messages strictly newer than `match`, across incoming and outgoing.
	static func directNewerCount(in context: ModelContext, userNum: Int64, than match: MessageSearchMatch) throws -> Int {
		let ts = match.timestamp
		let mid = match.messageId
		let detectionSensorPortNum: Int32 = 10
		let incomingNewer = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.fromUser?.num == userNum && $0.toUser != nil
					&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
					&& $0.messageTimestamp > ts
			}
		)
		let incomingSame = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.fromUser?.num == userNum && $0.toUser != nil
					&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
					&& $0.messageTimestamp == ts && $0.messageId > mid
			}
		)
		let outgoingNewer = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.toUser?.num == userNum
					&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
					&& $0.messageTimestamp > ts
			}
		)
		let outgoingSame = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.toUser?.num == userNum
					&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
					&& $0.messageTimestamp == ts && $0.messageId > mid
			}
		)
		return try context.fetchCount(incomingNewer) + context.fetchCount(incomingSame)
			+ context.fetchCount(outgoingNewer) + context.fetchCount(outgoingSame)
	}
}
