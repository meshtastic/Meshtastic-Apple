//
//  MessageDeduplicationTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/23/26.
//
//  Pins MessageEntity.deduplicatedByListID, the guard that keeps the message
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
		let result = MessageEntity.deduplicatedByListID([message(1), original, message(7), echo, message(9)])
		#expect(result.map(\.messageId) == [1, 42, 7, 9])
		#expect(result[1].messagePayload == "sent")
	}

	@Test func passesUniqueListsThroughUnchanged() {
		let input = [message(1), message(2), message(3)]
		let result = MessageEntity.deduplicatedByListID(input)
		#expect(result.map(\.messageId) == [1, 2, 3])
	}

	@Test("Two senders' messages that share a packet id are both shown; a sent message and its echo are one (review V55-1)")
	func twoSendersSamePacketId() {
		let fromA = message(42, payload: "from A")
		fromA.fromNum = 0xA
		fromA.messageKey = MessageEntity.key(fromNum: 0xA, messageId: 42)
		let fromB = message(42, payload: "from B")
		fromB.fromNum = 0xB
		fromB.messageKey = MessageEntity.key(fromNum: 0xB, messageId: 42)
		let echoOfB = message(42, payload: "echo of B")
		echoOfB.fromNum = 0xB
		echoOfB.messageKey = MessageEntity.key(fromNum: 0xB, messageId: 42)
		let result = MessageEntity.deduplicatedByListID([fromA, fromB, echoOfB])
		#expect(result.map(\.messagePayload) == ["from A", "from B"])
	}

	@Test("A row the backfill hasn't keyed yet has the key it will get, so it still matches its keyed copy")
	func unkeyedRowMatchesItsKey() {
		let unkeyed = message(7)
		unkeyed.fromNum = 0xC
		let keyed = message(7)
		keyed.fromNum = 0xC
		keyed.messageKey = MessageEntity.key(fromNum: 0xC, messageId: 7)
		#expect(unkeyed.listID == keyed.listID)
		#expect(MessageEntity.deduplicatedByListID([unkeyed, keyed]).count == 1)
	}

	@Test func emptyListIsEmpty() {
		#expect(MessageEntity.deduplicatedByListID([]).isEmpty)
	}
}
