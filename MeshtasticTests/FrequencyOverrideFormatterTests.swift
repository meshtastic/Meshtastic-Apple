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
		// Real band values. Note what 6 fraction digits means for a Float field: a
		// value the user typed as 433.175 is stored as 433.174988…, and at 6 digits the
		// field redisplays that instead of what was typed. Pinned deliberately — it is
		// the visible cost of a lossless round trip, and the alternative (fewer digits)
		// silently rounded the stored value instead. Values that are exact in binary
		// (906.875 = 906 + 7/8, 2412, 0) show clean.
		let cases: [(Float, String)] = [
			(0, "0"),                     // no override; must not render as 0,000000
			(433.175, "433,174988"),      // float noise surfaced, not rounded away
			(869.44165, "869,44165"),
			(906.875, "906,875"),         // exact in binary, so no noise
			(2_412, "2412")               // grouping off, so no separator at 2.4 GHz
		]

		for formatter in formatters {
			// Comma-decimal locale: the separator must round-trip, not just render.
			formatter.locale = Locale(identifier: "pt_PT")
			for (value, expected) in cases {
				let displayedValue = try #require(formatter.string(from: NSNumber(value: value)))
				let parsedValue = try #require(formatter.number(from: displayedValue)?.floatValue)

				#expect(displayedValue == expected)
				#expect(parsedValue == value)
			}
		}
	}

	/// The fields use whatever `Locale.current` is, so the default configuration has to
	/// round-trip too — the test above pins a locale and would pass even if it didn't.
	@Test func defaultLocaleRoundTripsWithoutRounding() throws {
		let formatter = frequencyOverrideFormatter
		for value in [Float(0), 433.175, 869.44165, 906.875, 2_412] {
			let displayed = try #require(formatter.string(from: NSNumber(value: value)))
			let parsed = try #require(formatter.number(from: displayed)?.floatValue)
			#expect(parsed == value, "\(displayed) did not round-trip")
		}
	}

	/// Zero means "no override" (see LoRaChannelCalculator), so it must stay short.
	@Test func zeroRendersWithoutPadding() throws {
		let formatter = frequencyOverrideFormatter
		let displayed = try #require(formatter.string(from: NSNumber(value: Float(0))))
		#expect(displayed == "0")
	}
}
