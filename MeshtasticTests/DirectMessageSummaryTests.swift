//
//  DirectMessageSummaryTests.swift
//  MeshtasticTests
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Direct message summaries")
struct DirectMessageSummaryTests {

	@Test("latest message and timestamp ties are order-independent")
	func latestMessageAndTimestampTiesAreOrderIndependent() throws {
		let peerNum: Int64 = 200
		let messages = [
			message(id: 10, timestamp: 100, payload: "oldest", from: peerNum, to: 100),
			message(id: 30, timestamp: 300, payload: "tie winner", from: 100, to: peerNum),
			message(id: 20, timestamp: 300, payload: "tie loser", from: peerNum, to: 100),
			message(id: 40, timestamp: 200, payload: "middle", from: 100, to: peerNum)
		]

		let forward = try DirectMessageSummaryReducer.summaries(for: [peerNum], messages: messages)
		let reverse = try DirectMessageSummaryReducer.summaries(for: [peerNum], messages: messages.reversed())

		#expect(forward == reverse)
		#expect(forward[peerNum] == DirectMessageSummary(
			messageId: 30,
			timestamp: 300,
			payload: "tie winner",
			unreadCount: 0
		))
	}

	@Test("actor scopes summaries to requested peers")
	@MainActor
	func actorScopesSummariesToRequestedPeers() async throws {
		let container = try makeContainer()
		let context = container.mainContext
		let local = insertUser(num: 100, into: context)
		let requestedPeer = insertUser(num: 200, into: context)
		let otherPeer = insertUser(num: 300, into: context)

		insertMessage(id: 1, timestamp: 100, payload: "incoming", participants: (requestedPeer, local), into: context)
		insertMessage(id: 2, timestamp: 200, payload: "outgoing", participants: (local, requestedPeer), into: context)
		insertMessage(id: 3, timestamp: 300, payload: "other peer", participants: (otherPeer, local), into: context)
		insertMessage(id: 4, timestamp: 400, payload: "channel", participants: (requestedPeer, nil), into: context)
		try context.save()

		let summaries = try await DirectMessageSummaryActor(modelContainer: container).summaries(for: [requestedPeer.num])

		#expect(summaries.keys.sorted() == [requestedPeer.num])
		#expect(summaries[requestedPeer.num]?.messageId == 2)
		#expect(summaries[requestedPeer.num]?.payload == "outgoing")
	}

	@Test("actor excludes emoji, admin, and detection messages")
	@MainActor
	func actorExcludesNonConversationMessages() async throws {
		let container = try makeContainer()
		let context = container.mainContext
		let local = insertUser(num: 110, into: context)
		let peer = insertUser(num: 210, into: context)

		insertMessage(id: 10, timestamp: 100, payload: "visible", participants: (peer, local), into: context)
		insertMessage(id: 11, timestamp: 200, payload: "emoji", participants: (peer, local), isEmoji: true, into: context)
		insertMessage(id: 12, timestamp: 300, payload: "admin", participants: (peer, local), admin: true, into: context)
		insertMessage(id: 13, timestamp: 400, payload: "detection", participants: (peer, local), portNum: 10, into: context)
		try context.save()

		let summary = try await DirectMessageSummaryActor(modelContainer: container).summaries(for: [peer.num])[peer.num]

		#expect(summary?.messageId == 10)
		#expect(summary?.payload == "visible")
	}

	@Test("actor counts only unread conversation messages")
	@MainActor
	func actorCountsUnreadConversationMessages() async throws {
		let container = try makeContainer()
		let context = container.mainContext
		let local = insertUser(num: 120, into: context)
		let peer = insertUser(num: 220, into: context)

		insertMessage(id: 20, timestamp: 100, payload: "unread incoming", participants: (peer, local), read: false, into: context)
		insertMessage(id: 21, timestamp: 200, payload: "read incoming", participants: (peer, local), read: true, into: context)
		insertMessage(id: 22, timestamp: 300, payload: "unread outgoing", participants: (local, peer), read: false, into: context)
		insertMessage(id: 23, timestamp: 400, payload: "excluded unread", participants: (peer, local), read: false, isEmoji: true, into: context)
		try context.save()

		let summary = try await DirectMessageSummaryActor(modelContainer: container).summaries(for: [peer.num])[peer.num]

		#expect(summary?.unreadCount == 2)
	}

	@Test("pre-cancelled actor request stops immediately")
	@MainActor
	func preCancelledActorRequestStopsImmediately() async throws {
		let actor = DirectMessageSummaryActor(modelContainer: try makeContainer())
		let task = Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return try await actor.summaries(for: [200])
		}

		await #expect(throws: CancellationError.self) {
			try await task.value
		}
	}

	@Test("container generation participates in refresh identity")
	func containerGenerationParticipatesInRefreshIdentity() {
		let original = DirectMessageSummaryRefreshID(
			usersKey: 1,
			unreadCount: 2,
			activeDeviceNum: 3,
			containerGeneration: 4
		)
		let replacement = DirectMessageSummaryRefreshID(
			usersKey: 1,
			unreadCount: 2,
			activeDeviceNum: 3,
			containerGeneration: 5
		)

		#expect(original != replacement)
	}

	@Test("actor cache follows container identity and generation")
	@MainActor
	func actorCacheFollowsContainerIdentityAndGeneration() throws {
		let firstContainer = try makeContainer()
		let secondContainer = try makeContainer()
		var cache = DirectMessageSummaryActorCache()

		let original = cache.actor(for: firstContainer, generation: 10)
		let reused = cache.actor(for: firstContainer, generation: 10)
		let newGeneration = cache.actor(for: firstContainer, generation: 11)
		let newContainer = cache.actor(for: secondContainer, generation: 11)

		#expect(original === reused)
		#expect(original !== newGeneration)
		#expect(newGeneration !== newContainer)
		#expect(cache.generation == 11)
	}

	@Test("cancelled burst refresh never reaches fetch phase")
	func cancelledBurstRefreshNeverReachesFetchPhase() async {
		let recorder = RefreshInvocationRecorder()
		let superseded = Task {
			try await DirectMessageSummaryRefreshLifecycle.waitForBurstToSettle(for: .seconds(1))
			await recorder.record(1)
		}
		for _ in 0..<3 {
			await Task.yield()
		}
		superseded.cancel()

		let current = Task {
			try await DirectMessageSummaryRefreshLifecycle.waitForBurstToSettle(for: .zero)
			await recorder.record(2)
		}

		await #expect(throws: CancellationError.self) {
			try await superseded.value
		}
		try? await current.value
		let invocations = await recorder.invocations
		#expect(invocations == [2])
	}

	@Test("in-flight reduction observes cancellation")
	func inFlightReductionObservesCancellation() async {
		let peerNum: Int64 = 230
		let messages = (0..<8).map {
			message(id: Int64($0), timestamp: Int32($0), payload: "message", from: peerNum, to: 130)
		}
		let cancellingMessages = messages.enumerated().lazy.map { index, message in
			if index == 3 {
				withUnsafeCurrentTask { $0?.cancel() }
			}
			return message
		}
		let task = Task {
			try DirectMessageSummaryReducer.summaries(for: [peerNum], messages: cancellingMessages)
		}

		await #expect(throws: CancellationError.self) {
			try await task.value
		}
	}

	private func message(
		id: Int64,
		timestamp: Int32,
		payload: String,
		from: Int64,
		to: Int64,
		read: Bool = true
	) -> DirectMessageSummaryMessage {
		DirectMessageSummaryMessage(
			messageId: id,
			timestamp: timestamp,
			payload: payload,
			read: read,
			fromNum: from,
			toNum: to
		)
	}

	@MainActor
	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(
			"DirectMessageSummaryTest-\(UUID().uuidString)",
			schema: schema,
			isStoredInMemoryOnly: true,
			allowsSave: true
		)
		return try ModelContainer(for: schema, configurations: configuration)
	}

	@MainActor
	private func insertUser(num: Int64, into context: ModelContext) -> UserEntity {
		let user = UserEntity()
		user.num = num
		context.insert(user)
		return user
	}

	@MainActor
	private func insertMessage(
		id: Int64,
		timestamp: Int32,
		payload: String,
		participants: (from: UserEntity, to: UserEntity?),
		read: Bool = true,
		isEmoji: Bool = false,
		admin: Bool = false,
		portNum: Int32 = 1,
		into context: ModelContext
	) {
		let message = MessageEntity()
		message.messageId = id
		message.messageTimestamp = timestamp
		message.messagePayload = payload
		message.fromUser = participants.from
		message.toUser = participants.to
		message.read = read
		message.isEmoji = isEmoji
		message.admin = admin
		message.portNum = portNum
		context.insert(message)
	}
}

private actor RefreshInvocationRecorder {
	private(set) var invocations: [Int] = []

	func record(_ invocation: Int) {
		invocations.append(invocation)
	}
}
