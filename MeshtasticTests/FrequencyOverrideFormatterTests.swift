import Foundation
import Testing

@testable import Meshtastic

@Suite("Frequency override formatting")
@MainActor
struct FrequencyOverrideFormatterTests {
	@Test func sharedAndViewFormattersUseRequiredPrecision() throws {
		let formatters = [
			frequencyOverrideFormatter,
			LoRaConfig(node: nil).floatFormatter,
			UserConfig(node: nil).floatFormatter
		]
		let cases: [(Float, String)] = [
			(0, "0"),
			(22.220015, "22,220015"),
			(869.44165, "869,44165"),
			(1_234.5, "1234,5")
		]

		for formatter in formatters {
			formatter.locale = Locale(identifier: "pt_PT")
			for (value, expected) in cases {
				let displayedValue = try #require(formatter.string(from: NSNumber(value: value)))
				let parsedValue = try #require(formatter.number(from: displayedValue)?.floatValue)

				#expect(displayedValue == expected)
				#expect(parsedValue == value)
			}
		}
	}
}
