// MentionParserTests.swift
// MeshtasticTests

import Testing
import Foundation
@testable import Meshtastic

// MARK: - MentionParser.mentionRanges

@Suite("MentionParser.mentionRanges")
struct MentionRangesTests {

	@Test func noMention_returnsEmpty() {
		let ranges = MentionParser.mentionRanges(in: "Hello world")
		#expect(ranges.isEmpty)
	}

	@Test func singleMention_returnsOneRange() {
		let ranges = MentionParser.mentionRanges(in: "Hello @!deadbeef!")
		#expect(ranges.count == 1)
		#expect(ranges.first?.hexId == "deadbeef")
	}

	@Test func multipleMentions_returnsAll() {
		let ranges = MentionParser.mentionRanges(in: "@!aabbccdd and @!11223344")
		#expect(ranges.count == 2)
		#expect(ranges[0].hexId == "aabbccdd")
		#expect(ranges[1].hexId == "11223344")
	}

	@Test func uppercaseHex_notMatched() {
		// Wire format is lowercase only
		let ranges = MentionParser.mentionRanges(in: "@!DEADBEEF")
		#expect(ranges.isEmpty)
	}

	@Test func tooShortHex_notMatched() {
		let ranges = MentionParser.mentionRanges(in: "@!abc")
		#expect(ranges.isEmpty)
	}

	@Test func tooLongHex_matchesFirst8() {
		// Pattern matches first 8 hex chars — the rest are plain text
		let ranges = MentionParser.mentionRanges(in: "@!deadbeef00")
		#expect(ranges.count == 1)
		#expect(ranges.first?.hexId == "deadbeef")
	}

	@Test func mentionMidSentence_matched() {
		let ranges = MentionParser.mentionRanges(in: "Hey @!12345678 how are you?")
		#expect(ranges.count == 1)
		#expect(ranges.first?.hexId == "12345678")
	}
}

// MARK: - MentionParser.nodeNum

@Suite("MentionParser.nodeNum")
struct MentionNodeNumTests {

	@Test func validHex_convertsToInt64() {
		#expect(MentionParser.nodeNum(from: "deadbeef") == Int64(UInt32(0xDEADBEEF)))
	}

	@Test func allZeroes_returnsZero() {
		#expect(MentionParser.nodeNum(from: "00000000") == 0)
	}

	@Test func maxUInt32_convertsCorrectly() {
		#expect(MentionParser.nodeNum(from: "ffffffff") == Int64(UInt32.max))
	}

	@Test func invalidHex_returnsNil() {
		#expect(MentionParser.nodeNum(from: "xyz!1234") == nil)
	}

	@Test func emptyString_returnsNil() {
		#expect(MentionParser.nodeNum(from: "") == nil)
	}
}

// MARK: - MentionParser.activeMentionQuery

@Suite("MentionParser.activeMentionQuery")
struct ActiveMentionQueryTests {

	@Test func atSignAlone_returnsEmptyQuery() {
		#expect(MentionParser.activeMentionQuery(in: "Hello @") == "")
	}

	@Test func partialName_returnsQuery() {
		#expect(MentionParser.activeMentionQuery(in: "Hey @Al") == "Al")
	}

	@Test func resolvedToken_returnsNil() {
		#expect(MentionParser.activeMentionQuery(in: "Hey @!deadbeef") == nil)
	}

	@Test func spaceAfterAt_returnsNil() {
		#expect(MentionParser.activeMentionQuery(in: "Hey @Alice world") == nil)
	}

	@Test func noAtSign_returnsNil() {
		#expect(MentionParser.activeMentionQuery(in: "Hello world") == nil)
	}

	@Test func atSignMidSentence_resolvedThenNewTrigger() {
		// Already resolved mention, then new trigger
		let text = "Pinging @!deadbeef and @Bo"
		#expect(MentionParser.activeMentionQuery(in: text) == "Bo")
	}

	@Test func newlineAfterAt_returnsNil() {
		#expect(MentionParser.activeMentionQuery(in: "Hey @Alice\n") == nil)
	}
}

// MARK: - MentionParser.insertMentionToken

@Suite("MentionParser.insertMentionToken")
struct InsertMentionTokenTests {

	private func makeUser(num: Int64, longName: String) -> UserEntity {
		let user = UserEntity()
		user.num = num
		user.longName = longName
		user.shortName = String(longName.prefix(4))
		user.userId = num.toHex()
		return user
	}

	@Test func replacesOpenTrigger() {
		let user = makeUser(num: 0xDEADBEEF, longName: "Alice")
		let result = MentionParser.insertMentionToken(into: "Hello @Al", user: user)
		#expect(result == "Hello @!deadbeef")
	}

	@Test func replacesEmptyTrigger() {
		let user = makeUser(num: 0x12345678, longName: "Bob")
		let result = MentionParser.insertMentionToken(into: "Hey @", user: user)
		#expect(result == "Hey @!12345678")
	}

	@Test func noTrigger_returnsUnchanged() {
		let user = makeUser(num: 0xABCDABCD, longName: "Charlie")
		let result = MentionParser.insertMentionToken(into: "Hello world", user: user)
		#expect(result == "Hello world")
	}

	@Test func alreadyResolved_returnsUnchanged() {
		let user = makeUser(num: 0xDEADBEEF, longName: "Alice")
		let text = "Hello @!deadbeef"
		let result = MentionParser.insertMentionToken(into: text, user: user)
		#expect(result == text)
	}

	@Test func preservesPrecedingText() {
		let user = makeUser(num: 0x00000001, longName: "Node")
		let result = MentionParser.insertMentionToken(into: "Check this out @N", user: user)
		#expect(result == "Check this out @!00000001")
	}
}

// MARK: - MentionParser.containsMention

@Suite("MentionParser.containsMention")
struct ContainsMentionTests {

	@Test func containsOwnMention_returnsTrue() {
		let text = "Hello @!deadbeef how are you"
		#expect(MentionParser.containsMention(of: Int64(UInt32(0xDEADBEEF)), in: text))
	}

	@Test func doesNotContainMention_returnsFalse() {
		let text = "Hello world"
		#expect(!MentionParser.containsMention(of: Int64(UInt32(0xDEADBEEF)), in: text))
	}

	@Test func differentNodeMention_returnsFalse() {
		let text = "Hello @!aabbccdd"
		#expect(!MentionParser.containsMention(of: Int64(UInt32(0xDEADBEEF)), in: text))
	}

	@Test func multipleMentions_detectsOwn() {
		let text = "@!00000001 and @!deadbeef are both here"
		#expect(MentionParser.containsMention(of: Int64(UInt32(0xDEADBEEF)), in: text))
		#expect(MentionParser.containsMention(of: 1, in: text))
	}

	@Test func zeroNodeNum_detected() {
		let text = "Msg @!00000000 test"
		#expect(MentionParser.containsMention(of: 0, in: text))
	}
}
