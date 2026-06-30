//
//  MessageAckStatusRefreshTests.swift
//  MeshtasticTests
//
//  Regression coverage for issue #2017: a sent message's status stayed on
//  "Waiting to be acknowledged" until the channel/conversation view was rebuilt.
//
//  ChannelMessageList / UserMessageList snapshot their rows into @State and only
//  reload when a lightweight "change token" differs. Before the fix that token keyed
//  only on the newest-message cursor (timestamp + messageId) and the total message
//  count — neither of which changes when an incoming ACK merely flips `receivedACK` /
//  `ackError` on an existing row, so the poll never reloaded and the row kept showing
//  the stale "Waiting…" state.
//
//  The fix folds an "acknowledged count" (messages whose ACK has resolved) into the
//  token. These tests mirror the exact SwiftData predicates the views use and lock in
//  the contract the fix depends on: the resolved count moves on every ack/fail/retry
//  transition, while the legacy token signals stay put.
//

import Testing
import Foundation
import SwiftData
@testable import Meshtastic

@Suite("Message ACK status refresh (#2017)")
@MainActor
struct MessageAckStatusRefreshTests {

	private var context: ModelContext { TestContainerProvider.shared.mainContext }

	private struct Cursor: Equatable {
		let timestamp: Int32
		let messageId: Int64
	}

	// MARK: - Channel-message mirrors of ChannelMessageList

	/// Total resolved (delivered + errored) count via the *production* helper, so the tests
	/// exercise the real predicates rather than a hand-mirrored copy that could silently drift.
	private func resolvedChannelCount(_ channelIndex: Int32) throws -> Int {
		let counts = try ChannelMessageList.resolvedAckCounts(in: context, channelIndex: channelIndex)
		return counts.delivered + counts.errored
	}

	/// Mirrors `ChannelMessageList.fetchMessageCount()` (the legacy token's `count`).
	private func totalChannelCount(_ channelIndex: Int32) throws -> Int {
		let descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.isEmoji == false
			}
		)
		return try context.fetchCount(descriptor)
	}

	/// Mirrors the legacy token's `latest` cursor: newest message by (timestamp, messageId).
	private func latestChannelCursor(_ channelIndex: Int32) throws -> Cursor? {
		var descriptor = FetchDescriptor<MessageEntity>(
			predicate: #Predicate<MessageEntity> {
				$0.channel == channelIndex && $0.toUser == nil && $0.isEmoji == false
			},
			sortBy: [
				SortDescriptor(\MessageEntity.messageTimestamp, order: .reverse),
				SortDescriptor(\MessageEntity.messageId, order: .reverse)
			]
		)
		descriptor.fetchLimit = 1
		return try context.fetch(descriptor).first.map { Cursor(timestamp: $0.messageTimestamp, messageId: $0.messageId) }
	}

	@discardableResult
	private func insertChannelMessage(channelIndex: Int32, messageId: Int64, timestamp: Int32 = 1_700_000_000) throws -> MessageEntity {
		let msg = MessageEntity()
		msg.channel = channelIndex
		msg.toUser = nil
		msg.isEmoji = false
		msg.messageId = messageId
		msg.messageTimestamp = timestamp
		msg.receivedACK = false
		msg.ackError = 0
		context.insert(msg)
		try context.save()
		return msg
	}

	// MARK: - Channel tests

	@Test func channelAck_movesResolvedCount_butNotLegacyToken() throws {
		let channelIndex: Int32 = 7_701
		let msg = try insertChannelMessage(channelIndex: channelIndex, messageId: 970_100_001)

		// Baseline: a sent-but-unacknowledged message is "Waiting…".
		#expect(try resolvedChannelCount(channelIndex) == 0)
		let baselineTotal = try totalChannelCount(channelIndex)
		let baselineCursor = try latestChannelCursor(channelIndex)
		#expect(baselineTotal == 1)

		// An incoming ACK flips `receivedACK` on the existing row.
		msg.receivedACK = true
		try context.save()

		// New signal moves → the list reloads and the row updates to "Acknowledged".
		#expect(try resolvedChannelCount(channelIndex) == 1)
		// Legacy token signals are blind to the ACK — this is exactly why the bug existed.
		#expect(try totalChannelCount(channelIndex) == baselineTotal)
		#expect(try latestChannelCursor(channelIndex) == baselineCursor)
	}

	@Test func channelErroredThenDelivered_movesToken() throws {
		// Finding #1 regression: a message that resolves to an error and is then delivered keeps
		// the *summed* resolved count constant (delivered +1, errored −1). The change token must
		// still move so the row updates from the error display to "Acknowledged".
		let channelIndex: Int32 = 7_705
		let msg = try insertChannelMessage(channelIndex: channelIndex, messageId: 970_500_001)

		msg.ackError = Int32(RoutingError.maxRetransmit.rawValue)
		try context.save()
		let errored = try ChannelMessageList.resolvedAckCounts(in: context, channelIndex: channelIndex)
		#expect(errored == (delivered: 0, errored: 1))

		// A later success packet flips ackError→0 and receivedACK→true.
		msg.ackError = 0
		msg.receivedACK = true
		try context.save()
		let delivered = try ChannelMessageList.resolvedAckCounts(in: context, channelIndex: channelIndex)

		#expect(delivered == (delivered: 1, errored: 0))
		// The summed count would be blind to this transition; the separate tallies are not.
		#expect(errored.delivered + errored.errored == delivered.delivered + delivered.errored)
		#expect(errored != delivered)
	}

	@Test func channelRoutingError_movesResolvedCount() throws {
		let channelIndex: Int32 = 7_702
		let msg = try insertChannelMessage(channelIndex: channelIndex, messageId: 970_200_001)
		#expect(try resolvedChannelCount(channelIndex) == 0)

		// A failed delivery resolves via a non-zero routing error (receivedACK stays false).
		msg.ackError = Int32(RoutingError.maxRetransmit.rawValue)
		try context.save()

		#expect(msg.ackError != 0)
		#expect(try resolvedChannelCount(channelIndex) == 1)
	}

	@Test func channelRetry_resetsResolvedCount() throws {
		let channelIndex: Int32 = 7_703
		let msg = try insertChannelMessage(channelIndex: channelIndex, messageId: 970_300_001)

		// Resolve as failed, then retry (RetryButton path) clears the ACK state back to waiting.
		msg.ackError = Int32(RoutingError.maxRetransmit.rawValue)
		try context.save()
		#expect(try resolvedChannelCount(channelIndex) == 1)

		msg.receivedACK = false
		msg.ackError = 0
		try context.save()

		// Back to "Waiting…", and the token moves again so the row reflects the reset.
		#expect(try resolvedChannelCount(channelIndex) == 0)
	}

	@Test func incomingChannelMessage_isNotCountedAsResolved() throws {
		let channelIndex: Int32 = 7_704
		// Incoming broadcast: same channel scope, but no ACK state (it isn't ours to ack).
		try insertChannelMessage(channelIndex: channelIndex, messageId: 970_400_001)

		#expect(try totalChannelCount(channelIndex) == 1)
		#expect(try resolvedChannelCount(channelIndex) == 0)
	}

	// MARK: - Direct-message mirrors of UserMessageList

	/// Total resolved (delivered + errored) count via the *production* helper, so the tests
	/// exercise the real predicates rather than a hand-mirrored copy that could silently drift.
	private func resolvedDirectCount(userNum: Int64) throws -> Int {
		let counts = try UserMessageList.resolvedAckCounts(in: context, toUserNum: userNum)
		return counts.delivered + counts.errored
	}

	private func makeUser(num: Int64) throws -> UserEntity {
		let user = UserEntity()
		user.num = num
		context.insert(user)
		try context.save()
		return user
	}

	@discardableResult
	private func insertOutgoingDirectMessage(to user: UserEntity, messageId: Int64, portNum: Int32 = 1) throws -> MessageEntity {
		let msg = MessageEntity()
		msg.toUser = user
		msg.isEmoji = false
		msg.admin = false
		msg.portNum = portNum
		msg.messageId = messageId
		msg.messageTimestamp = 1_700_000_000
		msg.receivedACK = false
		msg.ackError = 0
		context.insert(msg)
		try context.save()
		return msg
	}

	// MARK: - Direct-message tests

	@Test func directMessageAck_movesResolvedCount() throws {
		let user = try makeUser(num: 0x2017_0001)
		let msg = try insertOutgoingDirectMessage(to: user, messageId: 971_000_001)
		#expect(try resolvedDirectCount(userNum: user.num) == 0)

		msg.receivedACK = true
		try context.save()

		#expect(try resolvedDirectCount(userNum: user.num) == 1)
	}

	@Test func directMessageErroredThenDelivered_movesToken() throws {
		// Finding #1 regression, DM path: error then delivery leaves the summed count unchanged
		// but must still move the change token so the conversation reloads.
		let user = try makeUser(num: 0x2017_0004)
		let msg = try insertOutgoingDirectMessage(to: user, messageId: 971_000_004)

		msg.ackError = Int32(RoutingError.noResponse.rawValue)
		try context.save()
		let errored = try UserMessageList.resolvedAckCounts(in: context, toUserNum: user.num)
		#expect(errored == (delivered: 0, errored: 1))

		msg.ackError = 0
		msg.receivedACK = true
		try context.save()
		let delivered = try UserMessageList.resolvedAckCounts(in: context, toUserNum: user.num)

		#expect(delivered == (delivered: 1, errored: 0))
		#expect(errored.delivered + errored.errored == delivered.delivered + delivered.errored)
		#expect(errored != delivered)
	}

	@Test func directMessageRoutingError_movesResolvedCount() throws {
		let user = try makeUser(num: 0x2017_0002)
		let msg = try insertOutgoingDirectMessage(to: user, messageId: 971_000_002)
		#expect(try resolvedDirectCount(userNum: user.num) == 0)

		msg.ackError = Int32(RoutingError.noResponse.rawValue)
		try context.save()

		#expect(try resolvedDirectCount(userNum: user.num) == 1)
	}

	@Test func detectionSensorDirectMessage_isExcludedFromResolvedCount() throws {
		let user = try makeUser(num: 0x2017_0003)
		// Detection-sensor messages don't surface an ACK status row, so they must not
		// drive the conversation's refresh signal even once acknowledged.
		let msg = try insertOutgoingDirectMessage(to: user, messageId: 971_000_003, portNum: 10)

		msg.receivedACK = true
		try context.save()

		#expect(try resolvedDirectCount(userNum: user.num) == 0)
	}
}
