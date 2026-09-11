//
//  DirectMessageSummary.swift
//  Meshtastic
//

import Foundation
@preconcurrency import SwiftData

struct DirectMessageSummary: Equatable, Sendable {
	let messageId: Int64
	let timestamp: Int32
	let payload: String
	let unreadCount: Int
}

struct DirectMessageSummaryMessage: Sendable {
	let messageId: Int64
	let timestamp: Int32
	let payload: String
	let read: Bool
	let fromNum: Int64?
	let toNum: Int64?
}

struct DirectMessageSummaryRefreshID: Equatable {
	let usersKey: Int64
	let unreadCount: Int
	let activeDeviceNum: Int64
	let containerGeneration: Int
}

struct DirectMessageSummaryActorCache {
	private var actor: DirectMessageSummaryActor?
	private var containerIdentifier: ObjectIdentifier?
	private(set) var generation: Int?

	mutating func actor(for container: ModelContainer, generation: Int) -> DirectMessageSummaryActor {
		let identifier = ObjectIdentifier(container)
		if let actor, self.generation == generation, containerIdentifier == identifier {
			return actor
		}

		let replacement = DirectMessageSummaryActor(modelContainer: container)
		actor = replacement
		self.generation = generation
		containerIdentifier = identifier
		return replacement
	}
}

enum DirectMessageSummaryRefreshLifecycle {
	static let burstDelay: Duration = .milliseconds(100)

	static func waitForBurstToSettle(for delay: Duration = burstDelay) async throws {
		try await Task.sleep(for: delay)
		try Task.checkCancellation()
	}
}

enum DirectMessageSummaryReducer {
	static func summaries<Messages: Sequence>(
		for peerNums: Set<Int64>,
		messages: Messages
	) throws -> [Int64: DirectMessageSummary] where Messages.Element == DirectMessageSummaryMessage {
		try Task.checkCancellation()
		guard !peerNums.isEmpty else { return [:] }

		var accumulators = [Int64: DirectMessageSummaryAccumulator](minimumCapacity: peerNums.count)
		for message in messages {
			try Task.checkCancellation()
			record(message, peerNum: message.fromNum, peerNums: peerNums, accumulators: &accumulators)
			if message.toNum != message.fromNum {
				record(message, peerNum: message.toNum, peerNums: peerNums, accumulators: &accumulators)
			}
		}
		try Task.checkCancellation()
		return accumulators.compactMapValues(\.summary)
	}

	private static func record(
		_ message: DirectMessageSummaryMessage,
		peerNum: Int64?,
		peerNums: Set<Int64>,
		accumulators: inout [Int64: DirectMessageSummaryAccumulator]
	) {
		guard let peerNum, peerNums.contains(peerNum) else { return }
		accumulators[peerNum, default: DirectMessageSummaryAccumulator()].record(message)
	}
}

private struct DirectMessageSummaryAccumulator {
	private var latestMessageId = Int64.min
	private var latestTimestamp = Int32.min
	private var latestPayload = " "
	private var unreadCount = 0

	var summary: DirectMessageSummary? {
		guard latestMessageId != Int64.min else { return nil }
		return DirectMessageSummary(
			messageId: latestMessageId,
			timestamp: latestTimestamp,
			payload: latestPayload,
			unreadCount: unreadCount
		)
	}

	mutating func record(_ message: DirectMessageSummaryMessage) {
		if !message.read {
			unreadCount += 1
		}
		if message.timestamp > latestTimestamp
			|| (message.timestamp == latestTimestamp && message.messageId > latestMessageId) {
			latestMessageId = message.messageId
			latestTimestamp = message.timestamp
			latestPayload = message.payload
		}
	}
}

/// Fetches direct-message summaries on a background context. Only value types cross
/// the actor boundary; SwiftData entities remain isolated to this actor's context.
/// `ModelContext.fetch` is synchronous and cannot be interrupted once entered, so the
/// view coalesces bursts before calling here and this actor serializes calls as backpressure.
@ModelActor
actor DirectMessageSummaryActor {
	func summaries(for peerNums: Set<Int64>) throws -> [Int64: DirectMessageSummary] {
		try Task.checkCancellation()
		guard !peerNums.isEmpty else { return [:] }

		let detectionSensorPortNum: Int32 = 10
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.isEmoji == false && $0.admin == false && $0.portNum != detectionSensorPortNum
					&& $0.toUser != nil
			}
		)
		let messages = try modelContext.fetch(descriptor)
		try Task.checkCancellation()

		return try DirectMessageSummaryReducer.summaries(
			for: peerNums,
			messages: messages.lazy.map {
				DirectMessageSummaryMessage(
					messageId: $0.messageId,
					timestamp: $0.messageTimestamp,
					payload: $0.messagePayload ?? " ",
					read: $0.read,
					fromNum: $0.fromUser?.num,
					toNum: $0.toUser?.num
				)
			}
		)
	}
}
