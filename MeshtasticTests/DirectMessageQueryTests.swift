//
//  DirectMessageQueryTests.swift
//  MeshtasticTests
//
//  Feature 021 (T085): a direct-message conversation is one radio's thread with a node.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Direct message query per radio")
struct DirectMessageQueryTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B
	private let remote: Int64 = 0x1234_5678

	private struct Fixture {
		let container: ModelContainer
		let context: ModelContext
	}

	/// The remote node talked to through both radios, plus one row from before the backfill.
	private func makeFixture() throws -> Fixture {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("DirectMessageQueryTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		let container = try ModelContainer(for: schema, configurations: config)
		let context = ModelContext(container)
		var users: [Int64: UserEntity] = [:]
		for num in [radioA, radioB, remote] {
			let user = UserEntity()
			user.num = num
			context.insert(user)
			users[num] = user
		}
		func message(_ id: Int64, from: Int64, to: Int64, radio: Int64?, read: Bool = true, text: String) {
			let row = MessageEntity()
			row.messageId = id
			row.messageTimestamp = Int32(id)
			row.fromUser = users[from]
			row.toUser = users[to]
			row.localNodeNum = radio
			row.read = read
			row.messagePayload = text
			context.insert(row)
		}
		message(1, from: remote, to: radioA, radio: radioA, read: false, text: "X to A")
		message(2, from: remote, to: radioB, radio: radioB, read: false, text: "X to B")
		message(3, from: remote, to: radioB, radio: radioB, read: false, text: "X to B again")
		message(4, from: radioA, to: remote, radio: radioA, text: "A to X")
		message(5, from: radioB, to: remote, radio: radioB, text: "B to X")
		message(6, from: remote, to: radioA, radio: nil, text: "not backfilled")
		try context.save()
		return Fixture(container: container, context: context)
	}

	private func texts(_ rows: [MessageEntity]) -> Set<String> {
		Set(rows.compactMap(\.messagePayload))
	}

	@Test("One radio's thread has only its messages, plus rows without a radio yet")
	func perRadioThread() throws {
		let fixture = try makeFixture()
		let query = DirectMessageQuery(userNum: remote, radio: radioA)

		let incoming = try DirectMessageQuery.fetch(query.incoming(unreadOnly: false), limit: nil, in: fixture.context)
		let outgoing = try DirectMessageQuery.fetch(query.outgoing(unreadOnly: false), limit: nil, in: fixture.context)

		#expect(texts(incoming) == ["X to A", "not backfilled"])
		#expect(texts(outgoing) == ["A to X"])
		let unread = try DirectMessageQuery.fetch(query.incoming(unreadOnly: true), limit: nil, in: fixture.context)
		#expect(texts(unread) == ["X to A"])
	}

	@Test("Without a radio the conversation is the single-radio one: every message")
	func unfiltered() throws {
		let fixture = try makeFixture()
		let query = DirectMessageQuery(userNum: remote, radio: nil)

		let incoming = try DirectMessageQuery.fetch(query.incoming(unreadOnly: false), limit: nil, in: fixture.context)
		let outgoing = try DirectMessageQuery.fetch(query.outgoing(unreadOnly: false), limit: nil, in: fixture.context)

		#expect(incoming.count == 4)
		#expect(texts(outgoing) == ["A to X", "B to X"])
		// Newest first.
		#expect(incoming.first?.messageId == 6)
	}

	@Test("Radios with history in the conversation, and each one's unread count")
	func radiosWithHistory() throws {
		let fixture = try makeFixture()
		let radioC: Int64 = 0x0C0C_0C0C

		let result = DirectMessageQuery.radiosWithHistory(userNum: remote, among: [radioA, radioB, radioC], in: fixture.context)

		#expect(result.radios == [radioA, radioB])
		#expect(result.unread[radioA] == 1)
		#expect(result.unread[radioB] == 2)
		#expect(result.unread[radioC] == nil)
	}
}
