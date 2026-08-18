import Foundation
import Testing

@testable import Meshtastic

@Suite("Frequency override formatting")
struct FrequencyOverrideFormatterTests {
	@Test func usesOnlyRequiredFractionalDigits() throws {
		let formatter = frequencyOverrideFormatter
		formatter.locale = Locale(identifier: "pt_PT")
		let cases: [(Float, String)] = [
			(0, "0"),
			(22.220015, "22,220015"),
			(869.44165, "869,44165")
		]

		for (value, expected) in cases {
			let displayedValue = try #require(formatter.string(from: NSNumber(value: value)))
			let parsedValue = try #require(formatter.number(from: displayedValue)?.floatValue)

			#expect(displayedValue == expected)
			#expect(parsedValue == value)
		}
	}
}
