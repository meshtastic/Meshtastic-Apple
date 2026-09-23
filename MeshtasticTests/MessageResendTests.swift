//
//  MessageResendTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/23/26.
//
import Foundation
import SwiftData
import Testing

@testable import Meshtastic

/// Retrying a message sends the same one again rather than replacing it. It used to delete the
/// message and build a new one, which changed its id and its timestamp — the row left the
/// conversation and a different one appeared at the bottom, and a send that threw left nothing
/// behind at all.
@Suite("Message resend")
struct MessageResendTests {

	private func failedMessage(
		id: Int64 = 4242,
		sentAgo: TimeInterval = 10 * 60,
		ackError: Int32 = Int32(RoutingError.noResponse.rawValue)
	) -> MessageEntity {
		let message = MessageEntity()
		message.messageId = id
		message.messagePayload = "hello"
		message.messageTimestamp = Int32(Date().addingTimeInterval(-sentAgo).timeIntervalSince1970)
		message.receivedACK = false
		message.realACK = false
		message.ackError = ackError
		return message
	}

	@Test func aResendPutsTheMessageBackIntoSending() {
		let message = failedMessage()
		#expect(message.deliveryStatus(isDirectMessage: true).canRetry, "starts out failed")

		message.markResending()

		#expect(message.ackError == 0)
		#expect(!message.receivedACK)
		#expect(!message.realACK)
		#expect(message.deliveryStatus(isDirectMessage: true).text == MessageDeliveryStatus.sending.text)
	}

	@Test func aResendKeepsTheMessageId() {
		// The id is what makes this one message rather than two: the radio matches its ack on
		// it, replies point at it, and the echo coming back off the mesh is recognised as this
		// message rather than inserted again.
		let message = failedMessage(id: 987_654)
		message.markResending()
		#expect(message.messageId == 987_654)
	}

	@Test func aResendMovesTheTimestampForward() {
		// The one that is easy to miss. Status is derived from how long ago the message was
		// sent, so leaving the old timestamp in place would put it past sendAckTimeout
		// immediately and the row would show as failed again without anything going wrong.
		let sentLongAgo = MessageEntity.sendAckTimeout + 60
		let message = failedMessage(sentAgo: sentLongAgo, ackError: 0)
		#expect(message.deliveryStatus(isDirectMessage: true).canRetry, "aged out into not-delivered")

		let before = message.messageTimestamp
		message.markResending()

		#expect(message.messageTimestamp > before)
		#expect(message.deliveryStatus(isDirectMessage: true).text == MessageDeliveryStatus.sending.text,
				"an aged-out message goes back to sending, not straight back to failed")
	}
}
