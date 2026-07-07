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
		let acks = try ChannelMessageList.resolvedAckCounts(in: context, channelIndex: channelIndex)
		return acks.delivered + acks.errored
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
		// A message that resolves to an error and is then delivered keeps the *summed* resolved
		// count constant (delivered +1, errored −1). Tracking the tallies separately means a tally
		// still moves, so the token changes and the row updates from the error to "Acknowledged".
		let channelIndex: Int32 = 7_705
		let msg = try insertChannelMessage(channelIndex: channelIndex, messageId: 970_500_001)

		msg.ackError = Int32(RoutingError.maxRetransmit.rawValue)
		try context.save()
		let errored = try ChannelMessageList.resolvedAckCounts(in: context, channelIndex: channelIndex)
		#expect(errored.delivered == 0 && errored.errored == 1)

		// A later success packet flips ackError→0 and receivedACK→true.
		msg.ackError = 0
		msg.receivedACK = true
		try context.save()
		let delivered = try ChannelMessageList.resolvedAckCounts(in: context, channelIndex: channelIndex)

		#expect(delivered.delivered == 1 && delivered.errored == 0)
		// The summed count would be blind to this transition; the separate tallies are not.
		#expect(errored.delivered + errored.errored == delivered.delivered + delivered.errored)
		#expect(errored != delivered)
	}

	@Test func channelRetry_movesLatestCursorWhenTallyNetsZero() throws {
		// The net-zero-tally concern (two messages making offsetting same-type ACK transitions in
		// one poll window) can only arise via RetryButton, which is the sole route back to
		// "waiting" — and it *deletes* the failed message and *inserts* a fresh one rather than
		// mutating in place. So even when the errored tally nets to zero, the brand-new message
		// becomes the newest row and moves the legacy `latest` cursor, changing the token. This is
		// why a separate ackTimestamp signal isn't needed.
		let channelIndex: Int32 = 7_706
		let msgA = try insertChannelMessage(channelIndex: channelIndex, messageId: 970_600_001, timestamp: 1_700_000_000)
		let msgB = try insertChannelMessage(channelIndex: channelIndex, messageId: 970_600_002, timestamp: 1_700_000_010)
		msgB.ackError = Int32(RoutingError.maxRetransmit.rawValue)
		try context.save()
		let erroredBefore = try resolvedChannelCount(channelIndex)
		let cursorBefore = try latestChannelCursor(channelIndex)
		#expect(erroredBefore == 1)

		// A resolves to errored (+1). B is retried: the failed row is deleted and a new waiting row
		// is sent (newest timestamp). Errored tally nets to zero (A +1, B −1 via deletion)…
		msgA.ackError = Int32(RoutingError.maxRetransmit.rawValue)
		context.delete(msgB)
		try insertChannelMessage(channelIndex: channelIndex, messageId: 970_600_003, timestamp: 1_700_000_020)
		try context.save()

		#expect(try resolvedChannelCount(channelIndex) == erroredBefore)
		// …but the freshly-sent retry message is now the newest, so the `latest` cursor moved.
		#expect(try latestChannelCursor(channelIndex) != cursorBefore)
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

	@Test func incomingChannelMessage_isNotCountedAsResolved() throws {
		let channelIndex: Int32 = 7_704
		// An incoming broadcast from another node. Incoming channel messages are never
		// self-acknowledged — the device doesn't ACK its own received traffic — so receivedACK
		// stays false and ackError stays 0, which is the genuine state under test. (The channel
		// change-token predicate is intentionally sender-agnostic, so the guarantee is "unresolved
		// rows don't count", not "incoming rows are filtered out".)
		let sender = try makeUser(num: 0x2017_00AA)
		let incoming = try insertChannelMessage(channelIndex: channelIndex, messageId: 970_400_001)
		incoming.fromUser = sender
		try context.save()

		#expect(incoming.receivedACK == false && incoming.ackError == 0)
		#expect(try totalChannelCount(channelIndex) == 1)
		#expect(try resolvedChannelCount(channelIndex) == 0)
	}

	// MARK: - Direct-message mirrors of UserMessageList

	/// Total resolved (delivered + errored) count via the *production* helper, so the tests
	/// exercise the real predicates rather than a hand-mirrored copy that could silently drift.
	private func resolvedDirectCount(userNum: Int64) throws -> Int {
		let acks = try UserMessageList.resolvedAckCounts(in: context, toUserNum: userNum)
		return acks.delivered + acks.errored
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
		// DM path: error then delivery leaves the summed count unchanged, but a separate tally
		// still moves so the change token differs and the conversation reloads. (The net-zero
		// offsetting case is covered by the same retry-deletes-and-reinserts mechanism asserted in
		// channelRetry_movesLatestCursorWhenTallyNetsZero — it is identical for both lists.)
		let user = try makeUser(num: 0x2017_0004)
		let msg = try insertOutgoingDirectMessage(to: user, messageId: 971_000_004)

		msg.ackError = Int32(RoutingError.noResponse.rawValue)
		try context.save()
		let errored = try UserMessageList.resolvedAckCounts(in: context, toUserNum: user.num)
		#expect(errored.delivered == 0 && errored.errored == 1)

		msg.ackError = 0
		msg.receivedACK = true
		try context.save()
		let delivered = try UserMessageList.resolvedAckCounts(in: context, toUserNum: user.num)

		#expect(delivered.delivered == 1 && delivered.errored == 0)
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

	// MARK: - Message delivery status wording

	@Test func deliveryStatus_sendingUsesCanonicalText() throws {
		let msg = try insertChannelMessage(channelIndex: 7_707, messageId: 970_700_001)

		let status = msg.deliveryStatus(isDirectMessage: false)

		#expect(status.text == "Sending...")
		#expect(status.canRetry == false)
	}

	@Test func deliveryStatus_channelImplicitAckIsDeliveredToMesh() throws {
		let msg = try insertChannelMessage(channelIndex: 7_708, messageId: 970_800_001)
		msg.receivedACK = true
		try context.save()

		let status = msg.deliveryStatus(isDirectMessage: false)

		#expect(status.text == "Delivered to mesh")
		#expect(status.canRetry == false)
	}

	@Test func deliveryStatus_directImplicitAckWarnsAndCanRetry() throws {
		let user = try makeUser(num: 0x2017_0005)
		let msg = try insertOutgoingDirectMessage(to: user, messageId: 971_000_005)
		msg.receivedACK = true
		msg.realACK = false
		try context.save()

		let status = msg.deliveryStatus(isDirectMessage: true)

		#expect(status.text == "Relayed, not confirmed by recipient")
		#expect(status.detail == "A node relayed this message, but the recipient has not confirmed it.")
		#expect(status.canRetry == true)
	}

	@Test func deliveryStatus_directExplicitAckIsDeliveredToRecipient() throws {
		let user = try makeUser(num: 0x2017_0006)
		let msg = try insertOutgoingDirectMessage(to: user, messageId: 971_000_006)
		msg.receivedACK = true
		msg.realACK = true
		try context.save()

		let status = msg.deliveryStatus(isDirectMessage: true)

		#expect(status.text == "Delivered to recipient")
		#expect(status.canRetry == false)
	}

	@Test func deliveryStatus_maxRetransmitUsesMeshFailureText() throws {
		let msg = try insertChannelMessage(channelIndex: 7_709, messageId: 970_900_001)
		msg.ackError = Int32(RoutingError.maxRetransmit.rawValue)
		try context.save()

		let status = msg.deliveryStatus(isDirectMessage: false)

		#expect(status.text == "Failed to deliver to mesh")
		#expect(status.canRetry == true)
	}

	@Test func deliveryStatus_permanentFailuresDoNotOfferRetry() throws {
		let noChannel = MessageEntity()
		noChannel.ackError = Int32(RoutingError.noChannel.rawValue)
		let tooLarge = MessageEntity()
		tooLarge.ackError = Int32(RoutingError.tooLarge.rawValue)

		#expect(noChannel.deliveryStatus(isDirectMessage: false).text == "Channel/key mismatch")
		#expect(noChannel.deliveryStatus(isDirectMessage: false).canRetry == false)
		#expect(tooLarge.deliveryStatus(isDirectMessage: false).text == "Message is too large to send")
		#expect(tooLarge.deliveryStatus(isDirectMessage: false).canRetry == false)
	}

	@Test func deliveryStatus_pkiFailuresUseActionableKeyText() {
		let senderMissingRecipientKey = MessageEntity()
		senderMissingRecipientKey.ackError = Int32(RoutingError.pkiSendFailPublicKey.rawValue)
		let recipientMissingSenderKey = MessageEntity()
		recipientMissingSenderKey.ackError = Int32(RoutingError.pkiUnknownPubkey.rawValue)

		#expect(senderMissingRecipientKey.deliveryStatus(isDirectMessage: true).text == "Recipient key unavailable")
		#expect(recipientMissingSenderKey.deliveryStatus(isDirectMessage: true).text == "Recipient needs your key")
	}
}
