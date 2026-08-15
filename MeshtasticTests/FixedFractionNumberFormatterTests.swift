import Foundation
import Testing
@testable import Meshtastic

@Suite("FixedFractionNumberFormatter")
struct FixedFractionNumberFormatterTests {
	// Synthetic Locale identifiers cannot represent the independent iOS Number Format override, which remains simulator-validated.
	@Test func formatsFloatWithEnglishSeparatorsAndExactFractionDigits() {
		let result = FixedFractionNumberFormatter.format(
			Float(1_234.5),
			fractionDigits: 2,
			locale: Locale(identifier: "en_US")
		)

		#expect(result == "1,234.50")
	}

	@Test func formatsDoubleWithGermanSeparatorsAndExactFractionDigits() {
		let result = FixedFractionNumberFormatter.format(
			1_234.5,
			fractionDigits: 1,
			locale: Locale(identifier: "de_DE")
		)

		#expect(result == "1.234,5")
	}

	@Test func roundsHalfToEven() {
		let locale = Locale(identifier: "en_US")

		#expect(FixedFractionNumberFormatter.format(0.125, fractionDigits: 2, locale: locale) == "0.12")
		#expect(FixedFractionNumberFormatter.format(0.375, fractionDigits: 2, locale: locale) == "0.38")
	}
}
