// MARK: MessageSearchTests
//
//  Covers the per-conversation "find in conversation" content search (issue #2045):
//  case/diacritic-insensitive substring matching over the whole message store (including
//  historical messages), timeline ordering, conversation scoping, and the "newer count"
//  used to expand a windowed message list until a match is loaded.
//

import Testing
import Foundation
import SwiftData
@testable import Meshtastic

@Suite("MessageSearch")
@MainActor
struct MessageSearchTests {

	private func makeContext() -> ModelContext { ModelContext(sharedModelContainer) }

	@discardableResult
	private func addChannelMessage(_ context: ModelContext, id: Int64, channel: Int32, ts: Int32, text: String?, isEmoji: Bool = false) -> MessageEntity {
		let m = MessageEntity()
		m.messageId = id
		m.channel = channel
		m.messageTimestamp = ts
		m.messagePayload = text
		m.isEmoji = isEmoji
		m.toUser = nil
		context.insert(m)
		return m
	}

	@discardableResult
	private func addDirectMessage(_ context: ModelContext, id: Int64, between users: (from: UserEntity?, to: UserEntity?), ts: Int32, text: String?, isEmoji: Bool = false, admin: Bool = false, portNum: Int32 = 1) -> MessageEntity {
		let m = MessageEntity()
		m.messageId = id
		m.messageTimestamp = ts
		m.messagePayload = text
		m.isEmoji = isEmoji
		m.admin = admin
		m.portNum = portNum
		m.fromUser = users.from
		m.toUser = users.to
		context.insert(m)
		return m
	}

	private func makeUser(_ context: ModelContext, num: Int64) -> UserEntity {
		let u = UserEntity()
		u.num = num
		context.insert(u)
		return u
	}

	// MARK: Channel search

	@Test("Channel search finds substring matches, case/diacritic-insensitive, oldest→newest")
	func channelSubstringMatches() throws {
		let context = makeContext()
		let ch: Int32 = 70
		addChannelMessage(context, id: 7001, channel: ch, ts: 100, text: "Hello mesh world")
		addChannelMessage(context, id: 7002, channel: ch, ts: 200, text: "Nothing to see")
		addChannelMessage(context, id: 7003, channel: ch, ts: 300, text: "MESH rocks")      // case-insensitive
		addChannelMessage(context, id: 7004, channel: ch, ts: 400, text: "café meshtastic") // matches "mesh"
		try context.save()

		let matches = try MessageSearch.channelMatches(in: context, channelIndex: ch, query: "mesh")
		#expect(matches.map(\.messageId) == [7001, 7003, 7004])
	}

	@Test("Channel search is scoped to its channel and ignores emoji tapbacks")
	func channelScopingAndEmoji() throws {
		let context = makeContext()
		addChannelMessage(context, id: 7101, channel: 71, ts: 100, text: "target here")
		addChannelMessage(context, id: 7102, channel: 72, ts: 100, text: "target here")     // different channel
		addChannelMessage(context, id: 7103, channel: 71, ts: 200, text: "target", isEmoji: true) // emoji
		try context.save()

		let matches = try MessageSearch.channelMatches(in: context, channelIndex: 71, query: "target")
		#expect(matches.map(\.messageId) == [7101])
	}

	@Test("Empty/whitespace query returns no matches")
	func emptyQuery() throws {
		let context = makeContext()
		addChannelMessage(context, id: 7201, channel: 73, ts: 100, text: "anything")
		try context.save()
		#expect(try MessageSearch.channelMatches(in: context, channelIndex: 73, query: "   ").isEmpty)
	}

	@Test("Channel newer-count returns how many messages sit above a match")
	func channelNewerCount() throws {
		let context = makeContext()
		let ch: Int32 = 74
		addChannelMessage(context, id: 7401, channel: ch, ts: 100, text: "find me")
		addChannelMessage(context, id: 7402, channel: ch, ts: 200, text: "b")
		addChannelMessage(context, id: 7403, channel: ch, ts: 300, text: "c")
		try context.save()

		let matches = try MessageSearch.channelMatches(in: context, channelIndex: ch, query: "find me")
		let target = try #require(matches.first)
		// Two messages (7402, 7403) are newer than the ts=100 match.
		#expect(try MessageSearch.channelNewerCount(in: context, channelIndex: ch, than: target) == 2)
	}

	// MARK: Direct-message search

	@Test("Direct search spans incoming and outgoing, oldest→newest, scoped to the user")
	func directSpansBothDirections() throws {
		let context = makeContext()
		let me = makeUser(context, num: 9001)
		let them = makeUser(context, num: 9002)
		let other = makeUser(context, num: 9003)
		addDirectMessage(context, id: 8001, between: (them, me), ts: 100, text: "ping from them")   // incoming
		addDirectMessage(context, id: 8002, between: (me, them), ts: 200, text: "ping reply")        // outgoing
		addDirectMessage(context, id: 8003, between: (other, me), ts: 150, text: "ping from other")  // different user
		addDirectMessage(context, id: 8004, between: (me, them), ts: 250, text: "ping", isEmoji: true) // emoji excluded
		try context.save()

		let matches = try MessageSearch.directMatches(in: context, userNum: 9002, query: "ping")
		#expect(matches.map(\.messageId) == [8001, 8002])
	}

	@Test("Direct newer-count counts across both directions")
	func directNewerCount() throws {
		let context = makeContext()
		let me = makeUser(context, num: 9101)
		let them = makeUser(context, num: 9102)
		addDirectMessage(context, id: 8101, between: (them, me), ts: 100, text: "hello there")  // the match
		addDirectMessage(context, id: 8102, between: (me, them), ts: 200, text: "reply one")     // newer outgoing
		addDirectMessage(context, id: 8103, between: (them, me), ts: 300, text: "reply two")      // newer incoming
		try context.save()

		let matches = try MessageSearch.directMatches(in: context, userNum: 9102, query: "hello there")
		let target = try #require(matches.first)
		#expect(try MessageSearch.directNewerCount(in: context, userNum: 9102, than: target) == 2)
	}
}
