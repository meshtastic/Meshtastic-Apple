import Foundation
import Testing

@testable import Meshtastic

// MARK: - Base64 Conversion

@Suite("String Base64 Conversion")
struct StringBase64Tests {

	@Test func base64urlToBase64_replacesDashWithPlus() {
		let input = "abc-def"
		let result = input.base64urlToBase64()
		#expect(result.contains("+"))
		#expect(!result.contains("-"))
	}

	@Test func base64urlToBase64_replacesUnderscoreWithSlash() {
		let input = "abc_def"
		let result = input.base64urlToBase64()
		#expect(result.contains("/"))
		#expect(!result.contains("_"))
	}

	@Test func base64urlToBase64_addsPaddingWhenNeeded() {
		// Length 2 needs 2 padding chars
		#expect("ab".base64urlToBase64().hasSuffix("=="))
		// Length 3 needs 1 padding char
		#expect("abc".base64urlToBase64().hasSuffix("="))
		#expect("abc".base64urlToBase64() == "abc=")
		// Length 4 needs no padding
		#expect(!("abcd".base64urlToBase64().hasSuffix("=")))
	}

	@Test func base64urlToBase64_emptyStringRemainsEmpty() {
		#expect("".base64urlToBase64() == "")
	}

	@Test func base64ToBase64url_replacesPlusWithDash() {
		let input = "abc+def"
		let result = input.base64ToBase64url()
		#expect(result.contains("-"))
		#expect(!result.contains("+"))
	}

	@Test func base64ToBase64url_replacesSlashWithUnderscore() {
		let input = "abc/def"
		let result = input.base64ToBase64url()
		#expect(result.contains("_"))
		#expect(!result.contains("/"))
	}

	@Test func base64ToBase64url_stripsPadding() {
		let input = "abcd=="
		let result = input.base64ToBase64url()
		#expect(!result.contains("="))
	}

	@Test func roundTrip_base64urlToBase64AndBack() {
		let original = "SGVsbG8tV29ybGRf"
		let base64 = original.base64urlToBase64()
		let backToUrl = base64.base64ToBase64url()
		#expect(backToUrl == original)
	}

	@Test func base64ToBase64url_emptyStringRemainsEmpty() {
		#expect("".base64ToBase64url() == "")
	}
}

// MARK: - Emoji Detection

@Suite("String Emoji Detection")
struct StringEmojiTests {

	@Test func isEmoji_singleEmoji_returnsTrue() {
		#expect("😀".isEmoji())
		#expect("❤️".isEmoji())
		#expect("🇺🇸".isEmoji())
	}

	@Test func isEmoji_singleLetter_returnsFalse() {
		#expect(!"A".isEmoji())
		#expect(!"1".isEmoji())
	}

	@Test func isEmoji_emptyString_returnsFalse() {
		#expect(!"".isEmoji())
	}

	@Test func isEmoji_longString_returnsFalse() {
		#expect(!"Hello World".isEmoji())
	}

	@Test func onlyEmojis_allEmojis_returnsTrue() {
		#expect("😀🎉👍".onlyEmojis())
	}

	@Test func onlyEmojis_mixedContent_returnsFalse() {
		#expect(!"hello 😀".onlyEmojis())
	}

	@Test func onlyEmojis_emptyString_returnsFalse() {
		#expect(!"".onlyEmojis())
	}

	@Test func onlyEmojis_singleEmoji_returnsTrue() {
		#expect("🔥".onlyEmojis())
	}

	@Test func onlyEmojis_numbersOnly_returnsFalse() {
		#expect(!"12345".onlyEmojis())
	}
}

// MARK: - Character Emoji

@Suite("Character isEmoji")
struct CharacterEmojiTests {

	@Test func emoji_returnsTrue() {
		let char: Character = "😀"
		#expect(char.isEmoji)
	}

	@Test func letter_returnsFalse() {
		let char: Character = "A"
		#expect(!char.isEmoji)
	}

	@Test func digit_returnsFalse() {
		let char: Character = "5"
		#expect(!char.isEmoji)
	}

	@Test func heartEmoji_returnsTrue() {
		let char: Character = "❤"
		#expect(char.isEmoji)
	}
}

// MARK: - CamelCase Conversion

@Suite("String camelCaseToWords")
struct StringCamelCaseTests {

	@Test func simpleCamelCase_splitsCorrectly() {
		#expect("camelCase".camelCaseToWords() == "camel Case")
	}

	@Test func pascalCase_splitsCorrectly() {
		#expect("PascalCase".camelCaseToWords() == "Pascal Case")
	}

	@Test func multipleWords_splitsCorrectly() {
		#expect("myVariableName".camelCaseToWords() == "my Variable Name")
	}

	@Test func singleWord_unchanged() {
		#expect("hello".camelCaseToWords() == "hello")
	}

	@Test func emptyString_unchanged() {
		#expect("".camelCaseToWords() == "")
	}

	@Test func allCaps_unchanged() {
		// Pure uppercase with no transitions stays together
		#expect("ABC".camelCaseToWords() == "ABC")
	}

	@Test func acronymFollowedByWord_splitCorrectly() {
		#expect("HTTPSConnection".camelCaseToWords() == "HTTPS Connection")
	}
}

// MARK: - Subscript and Substring

@Suite("String Subscript & Substring")
struct StringSubscriptTests {

	@Test func intSubscript_returnsCorrectCharacter() {
		let str = "Hello"
		#expect(str[0] == "H")
		#expect(str[4] == "o")
	}

	@Test func substringFromIndex_returnsRemainder() {
		#expect("Hello".substring(fromIndex: 2) == "llo")
	}

	@Test func substringFromIndex_beyondLength_returnsEmpty() {
		#expect("Hi".substring(fromIndex: 10) == "")
	}

	@Test func substringToIndex_returnsPrefix() {
		#expect("Hello".substring(toIndex: 3) == "Hel")
	}

	@Test func substringToIndex_zero_returnsEmpty() {
		#expect("Hello".substring(toIndex: 0) == "")
	}

	@Test func substringToIndex_negative_returnsEmpty() {
		#expect("Hello".substring(toIndex: -1) == "")
	}

	@Test func rangeSubscript_returnsSubstring() {
		#expect("Hello"[1..<4] == "ell")
	}

	@Test func rangeSubscript_fullRange_returnsEntireString() {
		#expect("abc"[0..<3] == "abc")
	}

	@Test func length_returnsCount() {
		#expect("Hello".length == 5)
		#expect("".length == 0)
	}
}

// MARK: - Variation Selectors

@Suite("String Variation Selectors")
struct StringVariationSelectorTests {

	@Test func withoutVariationSelectors_removesEmojiVariationSelectors() {
		// U+2764 (heart) + U+FE0F (variation selector) → should strip FE0F
		let heart = "\u{2764}\u{FE0F}"
		let stripped = heart.withoutVariationSelectors
		#expect(!stripped.unicodeScalars.contains(where: { $0.value == 0xFE0F }))
	}

	@Test func withoutVariationSelectors_preservesASCIIWithVariationSelector() {
		// ASCII char followed by variation selector should be kept
		let input = "A\u{FE0F}"
		let result = input.withoutVariationSelectors
		#expect(result == input)
	}

	@Test func withoutVariationSelectors_plainASCII_unchanged() {
		let input = "Hello World"
		#expect(input.withoutVariationSelectors == input)
	}

	@Test func addingVariationSelectors_addsToEmojiWithoutPresentation() {
		// This tests that the function adds FE0F where needed
		let result = "\u{2764}".addingVariationSelectors
		#expect(result.unicodeScalars.contains(where: { $0.value == 0xFE0F }))
	}

	@Test func addingVariationSelectors_addsToEmojiWithoutExistingSelector() {
		// U+2764 without existing FE0F should gain one
		let input = "\u{2764}"
		let result = input.addingVariationSelectors
		let selectorCount = result.unicodeScalars.filter { $0.value == 0xFE0F }.count
		#expect(selectorCount == 1)
	}

	@Test func addingVariationSelectors_plainASCII_unchanged() {
		let input = "Hello"
		#expect(input.addingVariationSelectors == input)
	}
}

// MARK: - VoiceOver Formatting

@Suite("String formatNodeNameForVoiceOver")
struct StringVoiceOverTests {

	@Test func alphanumericNode_insertsSpace() {
		let result = "P130".formatNodeNameForVoiceOver()
		#expect(result.contains("P 130"))
	}

	@Test func pureLetters_noChange() {
		let result = "ABC".formatNodeNameForVoiceOver()
		#expect(result.contains("ABC"))
	}

	@Test func pureNumbers_noChange() {
		let result = "123".formatNodeNameForVoiceOver()
		#expect(result.contains("123"))
	}

	@Test func prefixesWithNode() {
		let result = "X1".formatNodeNameForVoiceOver()
		#expect(result.hasPrefix("Node"))
	}
}
