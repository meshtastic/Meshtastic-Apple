import Foundation
import Testing
import MeshtasticProtobufs

@testable import Meshtastic

// MARK: - XML Escaping

@Suite("String xmlEscaped")
struct XMLEscapingTests {

	@Test func escapesAmpersand() {
		#expect("A&B".xmlEscaped == "A&amp;B")
	}

	@Test func escapesLessThan() {
		#expect("A<B".xmlEscaped == "A&lt;B")
	}

	@Test func escapesGreaterThan() {
		#expect("A>B".xmlEscaped == "A&gt;B")
	}

	@Test func escapesDoubleQuote() {
		#expect("A\"B".xmlEscaped == "A&quot;B")
	}

	@Test func escapesSingleQuote() {
		#expect("A'B".xmlEscaped == "A&apos;B")
	}

	@Test func noEscapeNeeded() {
		#expect("Hello World".xmlEscaped == "Hello World")
	}

	@Test func multipleSpecialChars() {
		#expect("<tag attr='val'>".xmlEscaped == "&lt;tag attr=&apos;val&apos;&gt;")
	}

	@Test func emptyString() {
		#expect("".xmlEscaped == "")
	}
}

// MARK: - Team Color Mapping

@Suite("Team cotColorName")
struct TeamColorTests {

	@Test func allTeamColors() {
		#expect(Team.white.cotColorName == "White")
		#expect(Team.yellow.cotColorName == "Yellow")
		#expect(Team.orange.cotColorName == "Orange")
		#expect(Team.magenta.cotColorName == "Magenta")
		#expect(Team.red.cotColorName == "Red")
		#expect(Team.maroon.cotColorName == "Maroon")
		#expect(Team.purple.cotColorName == "Purple")
		#expect(Team.darkBlue.cotColorName == "Dark Blue")
		#expect(Team.blue.cotColorName == "Blue")
		#expect(Team.cyan.cotColorName == "Cyan")
		#expect(Team.teal.cotColorName == "Teal")
		#expect(Team.green.cotColorName == "Green")
		#expect(Team.darkGreen.cotColorName == "Dark Green")
		#expect(Team.brown.cotColorName == "Brown")
	}

	@Test func unspecified_defaultsCyan() {
		#expect(Team.unspecifedColor.cotColorName == "Cyan")
	}

	@Test func fromColorName_validColors() {
		#expect(Team.fromColorName("White") == .white)
		#expect(Team.fromColorName("Red") == .red)
		#expect(Team.fromColorName("Cyan") == .cyan)
		#expect(Team.fromColorName("Green") == .green)
	}

	@Test func fromColorName_caseInsensitive() {
		#expect(Team.fromColorName("white") == .white)
		#expect(Team.fromColorName("RED") == .red)
		#expect(Team.fromColorName("cyan") == .cyan)
	}

	@Test func fromColorName_darkBlueVariants() {
		#expect(Team.fromColorName("Dark Blue") == .darkBlue)
		#expect(Team.fromColorName("dark blue") == .darkBlue)
		#expect(Team.fromColorName("darkblue") == .darkBlue)
	}

	@Test func fromColorName_unknown_defaultsCyan() {
		#expect(Team.fromColorName("invalid") == .cyan)
		#expect(Team.fromColorName("") == .cyan)
	}
}

// MARK: - MemberRole Mapping

@Suite("MemberRole cotRoleName")
struct MemberRoleTests {

	@Test func allRoleNames() {
		#expect(MemberRole.teamMember.cotRoleName == "Team Member")
		#expect(MemberRole.teamLead.cotRoleName == "Team Lead")
		#expect(MemberRole.hq.cotRoleName == "HQ")
		#expect(MemberRole.sniper.cotRoleName == "Sniper")
		#expect(MemberRole.medic.cotRoleName == "Medic")
		#expect(MemberRole.forwardObserver.cotRoleName == "Forward Observer")
		#expect(MemberRole.rto.cotRoleName == "RTO")
		#expect(MemberRole.k9.cotRoleName == "K9")
	}

	@Test func unspecified_defaultsTeamMember() {
		#expect(MemberRole.unspecifed.cotRoleName == "Team Member")
	}

	@Test func fromRoleName_valid() {
		#expect(MemberRole.fromRoleName("Team Member") == .teamMember)
		#expect(MemberRole.fromRoleName("Team Lead") == .teamLead)
		#expect(MemberRole.fromRoleName("HQ") == .hq)
		#expect(MemberRole.fromRoleName("Sniper") == .sniper)
		#expect(MemberRole.fromRoleName("Medic") == .medic)
		#expect(MemberRole.fromRoleName("K9") == .k9)
	}

	@Test func fromRoleName_caseInsensitive() {
		#expect(MemberRole.fromRoleName("team member") == .teamMember)
		#expect(MemberRole.fromRoleName("sniper") == .sniper)
		#expect(MemberRole.fromRoleName("hq") == .hq)
	}

	@Test func fromRoleName_unknown_defaultsTeamMember() {
		#expect(MemberRole.fromRoleName("invalid") == .teamMember)
		#expect(MemberRole.fromRoleName("") == .teamMember)
	}
}

// MARK: - CoTMessage XML Roundtrip

@Suite("CoTMessage XML Roundtrip")
struct CoTMessageXMLRoundtripTests {

	@Test func pli_roundTrip() {
		let original = CoTMessage.pli(
			uid: "test-roundtrip",
			callsign: "RoundTrip",
			latitude: 37.7749,
			longitude: -122.4194,
			altitude: 50.0,
			speed: 10,
			course: 270,
			team: "Red",
			role: "Sniper",
			battery: 75
		)

		let xml = original.toXML()
		let parsed = CoTMessage.parse(from: xml)

		#expect(parsed != nil)
		#expect(parsed?.uid == "test-roundtrip")
		#expect(parsed?.type == "a-f-G-U-C")
		#expect(abs((parsed?.latitude ?? 0) - 37.7749) < 0.001)
		#expect(abs((parsed?.longitude ?? 0) - (-122.4194)) < 0.001)
		#expect(parsed?.contact?.callsign == "RoundTrip")
		#expect(parsed?.group?.name == "Red")
		#expect(parsed?.group?.role == "Sniper")
		#expect(parsed?.status?.battery == 75)
	}

	@Test func chat_roundTrip() {
		let original = CoTMessage.chat(
			senderUid: "sender-rt",
			senderCallsign: "Alice",
			message: "Hello World",
			chatroom: "All Chat Rooms"
		)

		let xml = original.toXML()
		let parsed = CoTMessage.parse(from: xml)

		#expect(parsed != nil)
		#expect(parsed?.type == "b-t-f")
		#expect(parsed?.chat?.message == "Hello World")
	}

	@Test func specialCharsInCallsign() {
		let original = CoTMessage(
			uid: "special-chars",
			type: "a-f-G-U-C",
			contact: CoTContact(callsign: "O'Brien & Sons")
		)

		let xml = original.toXML()
		#expect(xml.contains("O&apos;Brien &amp; Sons"))

		let parsed = CoTMessage.parse(from: xml)
		#expect(parsed != nil)
	}

	@Test func parse_nilForInvalidXML() {
		#expect(CoTMessage.parse(from: "not xml") == nil)
	}

	@Test func parse_nilForEmptyString() {
		#expect(CoTMessage.parse(from: "") == nil)
	}
}

// MARK: - Character isEmoji

@Suite("Character isEmoji")
struct CharacterIsEmojiTests {

	@Test func emoji_isTrue() {
		let emoji: Character = "😀"
		#expect(emoji.isEmoji)
	}

	@Test func letter_isFalse() {
		let letter: Character = "A"
		#expect(!letter.isEmoji)
	}

	@Test func digit_isFalse() {
		let digit: Character = "5"
		#expect(!digit.isEmoji)
	}

	@Test func heartEmoji_isTrue() {
		let heart: Character = "❤"
		#expect(heart.isEmoji)
	}
}

// MARK: - String isEmoji / onlyEmojis

@Suite("String Emoji Detection")
struct StringEmojiDetectionTests {

	@Test func singleEmoji_isEmoji() {
		#expect("😀".isEmoji())
	}

	@Test func letter_notEmoji() {
		#expect(!"A".isEmoji())
	}

	@Test func longString_notEmoji() {
		#expect(!"Hello World".isEmoji())
	}

	@Test func emptyString_notEmoji() {
		#expect(!"".isEmoji())
	}

	@Test func onlyEmojis_allEmoji() {
		#expect("😀🎉".onlyEmojis())
	}

	@Test func onlyEmojis_mixed() {
		#expect(!"Hello 😀".onlyEmojis())
	}

	@Test func onlyEmojis_empty() {
		#expect(!"".onlyEmojis())
	}
}

// MARK: - String withoutVariationSelectors

@Suite("String VariationSelectors Extended")
struct StringVariationSelectorExtTests {

	@Test func plainText_unchanged() {
		#expect("Hello".withoutVariationSelectors == "Hello")
	}

	@Test func emptyString_unchanged() {
		#expect("".withoutVariationSelectors == "")
	}
}

// MARK: - String formatNodeNameForVoiceOver

@Suite("String formatNodeNameForVoiceOver")
struct FormatNodeNameTests {

	@Test func alphanumeric_addsSpace() {
		let result = "P130".formatNodeNameForVoiceOver()
		#expect(result.contains("P 130"))
	}

	@Test func numbersOnly_noExtraSpace() {
		let result = "1234".formatNodeNameForVoiceOver()
		#expect(result.contains("1234"))
	}
}

// MARK: - String base64url

@Suite("String base64url")
struct Base64URLTests {

	@Test func base64urlToBase64_replacesDash() {
		let result = "abc-def".base64urlToBase64()
		#expect(result.contains("+"))
		#expect(!result.contains("-"))
	}

	@Test func base64urlToBase64_replacesUnderscore() {
		let result = "abc_def".base64urlToBase64()
		#expect(result.contains("/"))
		#expect(!result.contains("_"))
	}

	@Test func base64urlToBase64_addsPadding() {
		let result = "abc".base64urlToBase64()
		// "abc" is 3 chars, needs 1 padding to reach multiple of 4
		#expect(result.hasSuffix("="))
	}

	@Test func base64ToBase64url_replacesPlus() {
		let result = "abc+def==".base64ToBase64url()
		#expect(result.contains("-"))
		#expect(!result.contains("+"))
		#expect(!result.contains("="))
	}

	@Test func roundTrip() {
		let original = "SGVsbG8gV29ybGQ"
		let base64 = original.base64urlToBase64()
		let back = base64.base64ToBase64url()
		#expect(back == original)
	}
}

// MARK: - String camelCaseToWords

@Suite("String camelCaseToWords")
struct CamelCaseTests {

	@Test func simpleCamelCase() {
		#expect("helloWorld".camelCaseToWords() == "hello World")
	}

	@Test func multipleParts() {
		#expect("myLongVariableName".camelCaseToWords() == "my Long Variable Name")
	}

	@Test func alreadySeparated() {
		#expect("hello".camelCaseToWords() == "hello")
	}

	@Test func acronym() {
		#expect("parseHTTPResponse".camelCaseToWords() == "parse HTTP Response")
	}
}

// MARK: - String subscript

@Suite("String Subscript Extended")
struct StringSubscriptExtTests {

	@Test func intSubscript() {
		#expect("Hello"[0] == "H")
		#expect("Hello"[4] == "o")
	}

	@Test func rangeSubscript() {
		#expect("Hello"[0..<3] == "Hel")
	}

	@Test func substringFromIndex() {
		#expect("Hello".substring(fromIndex: 2) == "llo")
	}

	@Test func substringToIndex() {
		#expect("Hello".substring(toIndex: 3) == "Hel")
	}

	@Test func length() {
		#expect("Hello".length == 5)
		#expect("".length == 0)
	}
}
