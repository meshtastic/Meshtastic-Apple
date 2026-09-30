//
//  DirectMessageQuery.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation
import SwiftData

/// Queries for one direct-message conversation (feature 021, T085).
///
/// A direct message is between one of the user's radios and a remote node: only that radio can
/// decrypt it or reply as the node it was sent to. With `radio` set, the conversation is that
/// radio's thread (`MessageEntity.localNodeNum`); rows the backfill hasn't reached yet (no radio)
/// are included. With `radio` nil, the queries are the single-radio ones.
struct DirectMessageQuery {
	let userNum: Int64
	let radio: Int64?

	static let detectionSensorPortNum: Int32 = 10

	/// Messages the remote node sent.
	func incoming(unreadOnly: Bool) -> Predicate<MessageEntity> {
		let userNum = userNum
		let detectionSensorPortNum = Self.detectionSensorPortNum
		guard let radioNum = radio else {
			return #Predicate<MessageEntity> {
				$0.fromUser?.num == userNum
				&& $0.toUser != nil
				&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
				&& (!unreadOnly || $0.read == false)
			}
		}
		return #Predicate<MessageEntity> {
			$0.fromUser?.num == userNum
			&& $0.toUser != nil
			&& ($0.localNodeNum ?? radioNum) == radioNum
			&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
			&& (!unreadOnly || $0.read == false)
		}
	}

	/// Messages sent to the remote node.
	func outgoing(unreadOnly: Bool) -> Predicate<MessageEntity> {
		let userNum = userNum
		let detectionSensorPortNum = Self.detectionSensorPortNum
		guard let radioNum = radio else {
			return #Predicate<MessageEntity> {
				$0.toUser?.num == userNum
				&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
				&& (!unreadOnly || $0.read == false)
			}
		}
		return #Predicate<MessageEntity> {
			$0.toUser?.num == userNum
			&& ($0.localNodeNum ?? radioNum) == radioNum
			&& $0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
			&& (!unreadOnly || $0.read == false)
		}
	}

	/// Newest first, then by id, as the conversation shows them.
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

	/// The radios a direct conversation involves, as its Via picker lists them: the connected ones
	/// first, then the user's other radios with messages with `userNum`. The window's radio is
	/// always one of them, also while it's off with no messages, so its own thread shows and a
	/// reply goes through it and fails rather than from another radio (review V11 R11-3).
	static func conversationRadios(connected: [Int64], withHistory: Set<Int64>, windowRadio: Int64, userNum: Int64) -> [Int64] {
		let connected = connected.filter { $0 != userNum }
		var others = withHistory
		if windowRadio > 0, windowRadio != userNum {
			others.insert(windowRadio)
		}
		return connected + others.subtracting(connected).sorted()
	}

	/// Of `radios`, the ones with messages in a conversation with `userNum`, and how many of
	/// the remote node's messages each has unread. Counts only, so a long conversation isn't
	/// loaded; there is one query or three per radio, and the user has a handful of radios.
	static func radiosWithHistory(userNum: Int64, among radios: Set<Int64>, in context: ModelContext) -> (radios: Set<Int64>, unread: [Int64: Int]) {
		var withHistory: Set<Int64> = []
		var unread: [Int64: Int] = [:]
		for radioNum in radios where radioNum != userNum {
			let received = FetchDescriptor<MessageEntity>(predicate: #Predicate<MessageEntity> {
				$0.localNodeNum == radioNum && $0.fromUser?.num == userNum && $0.toUser != nil
			})
			let sent = FetchDescriptor<MessageEntity>(predicate: #Predicate<MessageEntity> {
				$0.localNodeNum == radioNum && $0.toUser?.num == userNum
			})
			let receivedCount = (try? context.fetchCount(received)) ?? 0
			guard receivedCount > 0 || ((try? context.fetchCount(sent)) ?? 0) > 0 else { continue }
			withHistory.insert(radioNum)
			guard receivedCount > 0 else { continue }
			let unreadDescriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate<MessageEntity> {
				$0.localNodeNum == radioNum && $0.fromUser?.num == userNum && $0.toUser != nil && $0.read == false
			})
			unread[radioNum] = (try? context.fetchCount(unreadDescriptor)) ?? 0
		}
		return (withHistory, unread)
	}
}
