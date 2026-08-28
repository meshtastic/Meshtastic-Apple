//
//  MessageDeduplicationTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/23/26.
//
//  Pins MessageEntity.deduplicatedByMessageId, the guard that keeps the message
//  lists from handing SwiftUI duplicate ForEach ids while a sent message and its
//  mesh echo briefly coexist across contexts (the 2.7.19 List batch-update crash).
//

import Testing

@testable import Meshtastic

@Suite("Message list deduplication")
struct MessageDeduplicationTests {

	private func message(_ id: Int64, payload: String = "") -> MessageEntity {
		let message = MessageEntity()
		message.messageId = id
		message.messagePayload = payload
		return message
	}

	@Test func keepsFirstOccurrenceAndOrder() {
		let original = message(42, payload: "sent")
		let echo = message(42, payload: "echo")
		let result = MessageEntity.deduplicatedByMessageId([message(1), original, message(7), echo, message(9)])
		#expect(result.map(\.messageId) == [1, 42, 7, 9])
		#expect(result[1].messagePayload == "sent")
	}

	@Test func passesUniqueListsThroughUnchanged() {
		let input = [message(1), message(2), message(3)]
		let result = MessageEntity.deduplicatedByMessageId(input)
		#expect(result.map(\.messageId) == [1, 2, 3])
	}

	@Test func emptyListIsEmpty() {
		#expect(MessageEntity.deduplicatedByMessageId([]).isEmpty)
	}
}
