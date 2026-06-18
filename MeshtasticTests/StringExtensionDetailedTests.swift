// StringExtensionDetailedTests.swift
// MeshtasticTests

import Testing
import Foundation
import MeshtasticProtobufs
@testable import Meshtastic

// MARK: - String Base64 Tests

@Suite("String Base64 Conversions")
struct StringBase64ConversionTests {

	@Test func base64urlToBase64_replacesChars() {
		let url = "SGVsbG8-V29ybGQ_"
		let result = url.base64urlToBase64()
		#expect(result.contains("+"))
		#expect(result.contains("/"))
		#expect(!result.contains("-"))
		#expect(!result.contains("_"))
	}

	@Test func base64ToBase64url_replacesChars() {
		let base64 = "SGVsbG8+V29ybGQ/=="
		let result = base64.base64ToBase64url()
		#expect(result.contains("-"))
		#expect(result.contains("_"))
		#expect(!result.contains("+"))
		#expect(!result.contains("/"))
		#expect(!result.contains("="))
	}

	@Test func roundTrip_base64urlToBase64AndBack() {
		let original = "SGVsbG8-V29ybGQ_"
		let base64 = original.base64urlToBase64()
		let backToUrl = base64.base64ToBase64url()
		#expect(backToUrl == original)
	}

	@Test func base64urlToBase64_addsPadding() {
		let noPad = "YQ"
		let result = noPad.base64urlToBase64()
		#expect(result.count % 4 == 0)
		#expect(result.hasSuffix("=="))
	}
}

// MARK: - String Emoji Tests

@Suite("String Emoji Detection Detailed")
struct StringEmojiDetectionDetailedTests {

	@Test func isEmoji_singleEmoji() {
		#expect("😀".isEmoji())
	}

	@Test func isEmoji_notEmoji() {
		#expect(!"Hello".isEmoji())
	}

	@Test func isEmoji_emptyString() {
		#expect(!"".isEmoji())
	}

	@Test func isEmoji_longString() {
		#expect(!"This is too long".isEmoji())
	}

	@Test func onlyEmojis_allEmojis() {
		#expect("😀👍".onlyEmojis())
	}

	@Test func onlyEmojis_mixedContent() {
		#expect(!"Hello 😀".onlyEmojis())
	}

	@Test func onlyEmojis_emptyString() {
		#expect(!"".onlyEmojis())
	}
}

// MARK: - String Manipulation Tests

@Suite("String Manipulation")
struct StringManipulationTests {

	@Test func camelCaseToWords_simple() {
		#expect("helloWorld".camelCaseToWords() == "hello World")
	}

	@Test func camelCaseToWords_multipleWords() {
		#expect("myVariableName".camelCaseToWords() == "my Variable Name")
	}

	@Test func camelCaseToWords_acronym() {
		#expect("parseHTMLContent".camelCaseToWords() == "parse HTML Content")
	}

	@Test func length() {
		#expect("Hello".length == 5)
		#expect("".length == 0)
	}

	@Test func subscript_singleChar() {
		#expect("Hello"[0] == "H")
		#expect("Hello"[4] == "o")
	}

	@Test func substring_fromIndex() {
		#expect("Hello World".substring(fromIndex: 6) == "World")
	}

	@Test func substring_toIndex() {
		#expect("Hello World".substring(toIndex: 5) == "Hello")
	}

	@Test func substring_fromIndex_beyondEnd() {
		#expect("Hi".substring(fromIndex: 100) == "")
	}

	@Test func substring_toIndex_negative() {
		#expect("Hi".substring(toIndex: -1) == "")
	}

	@Test func subscript_range() {
		#expect("Hello World"[0..<5] == "Hello")
	}

	@Test func formatNodeNameForVoiceOver() {
		let result = "P130".formatNodeNameForVoiceOver()
		#expect(result.contains("P 130"))
	}

	@Test func formatNodeNameForVoiceOver_noNumbers() {
		let result = "Alpha".formatNodeNameForVoiceOver()
		#expect(result.contains("Alpha"))
	}
}

// MARK: - Character Emoji Tests

@Suite("Character Emoji Property")
struct CharacterEmojiPropertyTests {

	@Test func emoji_isEmoji() {
		let char: Character = "😀"
		#expect(char.isEmoji)
	}

	@Test func letter_isNotEmoji() {
		let char: Character = "A"
		#expect(!char.isEmoji)
	}

	@Test func number_isNotEmoji() {
		let char: Character = "5"
		#expect(!char.isEmoji)
	}
}

// MARK: - Constants Tests

@Suite("Constants Values")
struct ConstantsValuesTests {

	@Test func maximumNodeNum() {
		#expect(Constants.maximumNodeNum == UInt32.max)
	}

	@Test func minimumNodeNum() {
		#expect(Constants.minimumNodeNum == 4)
	}

	@Test func nilValueIndicator() {
		#expect(Constants.nilValueIndicator == "--")
	}
}

// MARK: - Bundle Tests

@Suite("Bundle Extensions Detailed")
struct BundleExtensionDetailedTests {

	@Test func appName_notEmpty() {
		#expect(!Bundle.main.appName.isEmpty || Bundle.main.appName == "⚠️")
	}

	@Test func appBuild_notEmpty() {
		#expect(!Bundle.main.appBuild.isEmpty || Bundle.main.appBuild == "⚠️")
	}

	@Test func isDebug_inTestEnvironment() {
		#if DEBUG
		#expect(Bundle.main.isDebug == true)
		#else
		#expect(Bundle.main.isDebug == false)
		#endif
	}
}

// MARK: - IntervalConfiguration Tests

@Suite("IntervalConfiguration Detailed")
struct IntervalConfigurationDetailedTests {

	@Test func allCases_count() {
		#expect(IntervalConfiguration.allCases.count == 10)
	}

	@Test func all_returnsAllFixedCases() {
		let cases = IntervalConfiguration.all.allowedCases
		#expect(cases.count == FixedUpdateIntervals.allCases.count)
	}

	@Test func broadcastShort_hasUnset() {
		let cases = IntervalConfiguration.broadcastShort.allowedCases
		#expect(cases.contains(.unset))
	}

	@Test func broadcastLong_noShortIntervals() {
		let cases = IntervalConfiguration.broadcastLong.allowedCases
		#expect(!cases.contains(.oneMinute))
		#expect(!cases.contains(.fifteenMinutes))
	}

	@Test func nagTimeout_shortIntervals() {
		let cases = IntervalConfiguration.nagTimeout.allowedCases
		#expect(cases.contains(.oneSecond))
		#expect(cases.contains(.oneMinute))
		#expect(!cases.contains(.oneHour))
	}

	@Test func rangeTestSender_mediumIntervals() {
		let cases = IntervalConfiguration.rangeTestSender.allowedCases
		#expect(cases.contains(.fifteenSeconds))
		#expect(cases.contains(.oneHour))
		#expect(!cases.contains(.twentyFourHours))
	}
}

// MARK: - FixedUpdateIntervals Tests

@Suite("FixedUpdateIntervals")
struct FixedUpdateIntervalsEnumTests {

	@Test func allCases_count() {
		#expect(FixedUpdateIntervals.allCases.count == 26)
	}

	@Test func never_isMaxInt() {
		#expect(FixedUpdateIntervals.never.rawValue == 2147483647)
	}

	@Test func hashable() {
		let set: Set<FixedUpdateIntervals> = [.oneSecond, .fiveSeconds, .oneSecond]
		#expect(set.count == 2)
	}
}

// MARK: - UpdateInterval Tests

@Suite("UpdateInterval Struct")
struct UpdateIntervalStructTests {

	@Test func fromKnownValue() {
		let interval = UpdateInterval(from: 3600)
		#expect(interval.intValue == 3600)
		#expect(interval.description == "One Hour")
	}

	@Test func fromUnknownValue_manual() {
		let interval = UpdateInterval(from: 42)
		#expect(interval.intValue == 42)
		#expect(interval.description.contains("42"))
	}

	@Test func id_fixed() {
		let interval = UpdateInterval(from: 60)
		#expect(interval.id == "fixed_60")
	}

	@Test func id_manual() {
		let interval = UpdateInterval(from: 99)
		#expect(interval.id == "manual_99")
	}

	@Test func hashable() {
		let a = UpdateInterval(from: 3600)
		let b = UpdateInterval(from: 3600)
		#expect(a == b)
	}

	@Test func allFixedDescriptions_nonEmpty() {
		for fixedCase in FixedUpdateIntervals.allCases {
			let interval = UpdateInterval(from: fixedCase.rawValue)
			#expect(!interval.description.isEmpty)
		}
	}
}

// MARK: - OutputIntervals Tests

@Suite("OutputIntervals Enum")
struct OutputIntervalsEnumTests {

	@Test func allCases_count() {
		#expect(OutputIntervals.allCases.count == 10)
	}

	@Test func allCases_haveDescriptions() {
		for interval in OutputIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func identifiable() {
		for interval in OutputIntervals.allCases {
			#expect(interval.id == interval.rawValue)
		}
	}

	@Test func unset_isZero() {
		#expect(OutputIntervals.unset.rawValue == 0)
	}

	@Test func oneSecond_is1000ms() {
		#expect(OutputIntervals.oneSecond.rawValue == 1000)
	}
}

// MARK: - NodeInfo Extensions Tests

@Suite("NodeInfo isValidPosition")
struct NodeInfoIsValidPositionTests {

	private func nodeInfo(lat: Int32, long: Int32) -> NodeInfo {
		var info = NodeInfo()
		var pos = Position()
		pos.latitudeI = lat
		pos.longitudeI = long
		info.position = pos
		return info
	}

	@Test func validPosition() {
		#expect(nodeInfo(lat: 377749000, long: -1224194000).isValidPosition == true)
	}

	@Test func nullIsland_invalid() {
		#expect(nodeInfo(lat: 0, long: 0).isValidPosition == false)
	}

	@Test func applePark_invalid() {
		#expect(nodeInfo(lat: 373346000, long: -1220090000).isValidPosition == false)
	}

	@Test func noPosition_invalid() {
		let info = NodeInfo()
		#expect(info.hasPosition == false)
		#expect(info.isValidPosition == false)
	}
}

@Suite("Position hasValidCoordinates")
struct PositionHasValidCoordinatesTests {

	private func position(lat: Int32, long: Int32) -> Position {
		var pos = Position()
		pos.latitudeI = lat
		pos.longitudeI = long
		return pos
	}

	@Test func realCoordinates_valid() {
		#expect(position(lat: 377749000, long: -1224194000).hasValidCoordinates == true)
	}

	@Test func nullIsland_invalid() {
		#expect(position(lat: 0, long: 0).hasValidCoordinates == false)
	}

	@Test func applePark_invalid() {
		#expect(position(lat: 373346000, long: -1220090000).hasValidCoordinates == false)
	}

	// A position with either component zero is treated as "no location" app-wide (it would
	// not render via nodeCoordinate), so it must not count as valid — matching the convention.
	@Test func latitudeZero_invalid() {
		#expect(position(lat: 0, long: -1224194000).hasValidCoordinates == false)
	}

	@Test func longitudeZero_invalid() {
		#expect(position(lat: 377749000, long: 0).hasValidCoordinates == false)
	}

	// Sharing only one coordinate with Apple Park is a real position, not the placeholder.
	@Test func appleParkLatitudeOnly_valid() {
		#expect(position(lat: 373346000, long: -1224194000).hasValidCoordinates == true)
	}

	@Test func appleParkLongitudeOnly_valid() {
		#expect(position(lat: 377749000, long: -1220090000).hasValidCoordinates == true)
	}
}

// MARK: - LogRecord StringRepresentation Tests

@Suite("LogRecord StringRepresentation")
struct LogRecordStringRepresentationTests {

	@Test func debugLevel() {
		var record = LogRecord()
		record.level = .debug
		record.message = "test message"
		record.source = ""
		#expect(record.stringRepresentation.contains("DEBUG"))
		#expect(record.stringRepresentation.contains("test message"))
	}

	@Test func infoLevel() {
		var record = LogRecord()
		record.level = .info
		record.message = "info msg"
		record.source = ""
		#expect(record.stringRepresentation.contains("INFO"))
	}

	@Test func warningLevel() {
		var record = LogRecord()
		record.level = .warning
		record.message = "warn msg"
		record.source = ""
		#expect(record.stringRepresentation.contains("WARN"))
	}

	@Test func errorLevel() {
		var record = LogRecord()
		record.level = .error
		record.message = "error msg"
		record.source = ""
		#expect(record.stringRepresentation.contains("ERROR"))
	}

	@Test func criticalLevel() {
		var record = LogRecord()
		record.level = .critical
		record.message = "crit msg"
		record.source = ""
		#expect(record.stringRepresentation.contains("CRIT"))
	}

	@Test func withSource() {
		var record = LogRecord()
		record.level = .info
		record.message = "hello"
		record.source = "MyModule"
		let result = record.stringRepresentation
		#expect(result.contains("[MyModule]"))
		#expect(result.contains("hello"))
	}
}
