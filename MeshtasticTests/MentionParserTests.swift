// MentionParserTests.swift
// MeshtasticTests

import Testing
import Foundation
import SwiftData
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

	@Test func tooLongHex_notMatched() {
		// The wire format is exactly 8 hex digits — a longer run is not a mention,
		// and must not be misread as a mention of its first 8 digits.
		let ranges = MentionParser.mentionRanges(in: "@!deadbeef00")
		#expect(ranges.isEmpty)
	}

	@Test func eightHexFollowedByNonHex_matched() {
		// Non-hex characters end the token, so punctuation and words can follow.
		let ranges = MentionParser.mentionRanges(in: "@!deadbeefg and @!12345678, hi")
		#expect(ranges.map(\.hexId) == ["deadbeef", "12345678"])
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

	@Test func longerHexRun_isNotSelfMention() {
		// A malformed longer token must not notify the node matching its first 8 digits.
		let text = "Hello @!deadbeef00"
		#expect(!MentionParser.containsMention(of: Int64(UInt32(0xDEADBEEF)), in: text))
	}
}

// MARK: - MentionParser.resolveMentions

@Suite("MentionParser.resolveMentions", .serialized)
@MainActor
struct ResolveMentionsTests {

	/// Returns the container (not just its context) — the context traps if the
	/// container deallocates underneath it, so tests must keep it alive.
	private func makeContainer(userName: String?, num: Int64) throws -> ModelContainer {
		// Unique config name per test: SwiftData treats two containers sharing a name and
		// schema as the same store, and that collision resets other live contexts (see
		// the SharedTestContainer notes in MeshtasticAPIBundledSeedTests).
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let container = try ModelContainer(
			for: schema,
			configurations: ModelConfiguration(
				"MentionResolveTest-\(UUID().uuidString)",
				schema: schema,
				isStoredInMemoryOnly: true,
				allowsSave: true
			)
		)
		let user = UserEntity()
		user.num = num
		user.longName = userName
		container.mainContext.insert(user)
		try container.mainContext.save()
		return container
	}

	@Test func resolvesTokenToMarkdownLink() throws {
		let container = try makeContainer(userName: "Alice", num: Int64(UInt32(0xDEADBEEF)))
		let resolved = MentionParser.resolveMentions(in: "Hi @!deadbeef", context: container.mainContext)
		#expect(resolved == "Hi [@Alice](meshtastic:///nodes?nodenum=3735928559)")
	}

	@Test func escapesMarkdownControlCharactersInDisplayName() throws {
		// Names come from mesh data — brackets/parens/backslashes must not be able to
		// break or restructure the generated markdown link.
		let container = try makeContainer(userName: #"Ali]ce (the \best*"#, num: Int64(UInt32(0xDEADBEEF)))
		let resolved = MentionParser.resolveMentions(in: "Hi @!deadbeef", context: container.mainContext)
		#expect(resolved == #"Hi [@Ali\]ce \(the \\best\*](meshtastic:///nodes?nodenum=3735928559)"#)
		// The whole message must still parse as markdown with the name intact.
		let attributed = try AttributedString(markdown: resolved)
		#expect(String(attributed.characters).contains(#"@Ali]ce (the \best*"#))
	}

	@Test func unknownNodeFallsBackToHexId() throws {
		let container = try makeContainer(userName: "Alice", num: 1)
		let resolved = MentionParser.resolveMentions(in: "Hi @!deadbeef", context: container.mainContext)
		#expect(resolved == #"Hi [@\!deadbeef](meshtastic:///nodes?nodenum=3735928559)"#)
	}
}
