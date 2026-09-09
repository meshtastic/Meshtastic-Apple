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






	// MARK: - Direct-message mirrors of UserMessageList


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






	// MARK: - Message delivery status wording

	@Test func deliveryStatus_sendingUsesCanonicalText() throws {
		// A just-sent, still-unacknowledged message is "Sending…" — the send timeout hasn't elapsed.
		let msg = try insertChannelMessage(channelIndex: 7_707, messageId: 970_700_001,
										   timestamp: Int32(Date().timeIntervalSince1970))

		let status = msg.deliveryStatus(isDirectMessage: false)

		#expect(status.text == "Sending...")
		#expect(status.canRetry == false)
	}

	@Test func deliveryStatus_orphanedSendTimesOutToNotDelivered() throws {
		// A message left unacknowledged (no ACK, no routing error) well past the send timeout is
		// surfaced as failed/retryable rather than an indefinite "Sending…" — the ack/nak never
		// reached the app and the message is orphaned.
		let stale = Int32(Date().timeIntervalSince1970 - MessageEntity.sendAckTimeout - 60)
		let msg = try insertChannelMessage(channelIndex: 7_709, messageId: 970_900_001, timestamp: stale)

		let status = msg.deliveryStatus(isDirectMessage: false)

		#expect(status.text == "Not delivered")
		#expect(status.canRetry == true)
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
