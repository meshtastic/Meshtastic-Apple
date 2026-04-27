import Foundation
import SwiftUI
import Testing

@testable import Meshtastic

// MARK: - RoutingError

@Suite("RoutingError Properties")
struct RoutingErrorTests {

	@Test func allCases_haveNonEmptyDisplay() {
		for error in RoutingError.allCases {
			#expect(!error.display.isEmpty, "RoutingError.\(error) has empty display")
		}
	}

	@Test func none_displayIsAcknowledged() {
		#expect(RoutingError.none.display == "Acknowledged")
	}

	@Test func none_canRetryIsFalse() {
		#expect(!RoutingError.none.canRetry)
	}

	@Test func tooLarge_canRetryIsFalse() {
		#expect(!RoutingError.tooLarge.canRetry)
	}

	@Test func timeout_canRetryIsTrue() {
		#expect(RoutingError.timeout.canRetry)
	}

	@Test func noRoute_canRetryIsTrue() {
		#expect(RoutingError.noRoute.canRetry)
	}

	@Test func maxRetransmit_canRetryIsTrue() {
		#expect(RoutingError.maxRetransmit.canRetry)
	}

	@Test func pkiFailed_canRetryIsTrue() {
		#expect(RoutingError.pkiFailed.canRetry)
	}

	@Test func rateLimitExceeded_canRetryIsTrue() {
		#expect(RoutingError.rateLimitExceeded.canRetry)
	}

	@Test func none_colorIsSecondary() {
		#expect(RoutingError.none.color == Color.secondary)
	}

	@Test func nonRetryable_colorIsRed() {
		#expect(RoutingError.tooLarge.color == Color.red)
	}

	@Test func retryable_colorIsOrange() {
		#expect(RoutingError.timeout.color == Color.orange)
		#expect(RoutingError.noRoute.color == Color.orange)
	}

	@Test func allCases_haveUniqueRawValues() {
		let rawValues = RoutingError.allCases.map(\.rawValue)
		#expect(Set(rawValues).count == rawValues.count)
	}

	@Test func identifiable_idMatchesRawValue() {
		for error in RoutingError.allCases {
			#expect(error.id == error.rawValue)
		}
	}
}

// MARK: - Aqi

@Suite("Air Quality Index")
struct AqiTests {

	@Test func getAqi_goodRange_returnsGood() {
		#expect(Aqi.getAqi(for: 0) == .good)
		#expect(Aqi.getAqi(for: 25) == .good)
		#expect(Aqi.getAqi(for: 50) == .good)
	}

	@Test func getAqi_moderateRange_returnsModerate() {
		#expect(Aqi.getAqi(for: 51) == .moderate)
		#expect(Aqi.getAqi(for: 100) == .moderate)
	}

	@Test func getAqi_sensitiveRange_returnsSensitive() {
		#expect(Aqi.getAqi(for: 101) == .sensitive)
		#expect(Aqi.getAqi(for: 150) == .sensitive)
	}

	@Test func getAqi_unhealthyRange_returnsUnhealthy() {
		#expect(Aqi.getAqi(for: 151) == .unhealthy)
		#expect(Aqi.getAqi(for: 200) == .unhealthy)
	}

	@Test func getAqi_veryUnhealthyRange_returnsVeryUnhealthy() {
		#expect(Aqi.getAqi(for: 201) == .veryUnhealthy)
		#expect(Aqi.getAqi(for: 300) == .veryUnhealthy)
	}

	@Test func getAqi_hazardousRange_returnsHazardous() {
		#expect(Aqi.getAqi(for: 301) == .hazardous)
		#expect(Aqi.getAqi(for: 500) == .hazardous)
	}

	@Test func allCases_haveNonEmptyDescription() {
		for aqi in Aqi.allCases {
			#expect(!aqi.description.isEmpty)
		}
	}

	@Test func allCases_haveColors() {
		#expect(Aqi.good.color == .green)
		#expect(Aqi.moderate.color == .yellow)
		#expect(Aqi.hazardous.color == .magenta)
	}

	@Test func allCases_rangesDoNotOverlap() {
		let sorted = Aqi.allCases.sorted { $0.rawValue < $1.rawValue }
		for i in 0..<sorted.count - 1 {
			#expect(sorted[i].range.upperBound <= sorted[i + 1].range.lowerBound,
				"Range overlap between \(sorted[i]) and \(sorted[i + 1])")
		}
	}

	@Test func identifiable_idMatchesRawValue() {
		for aqi in Aqi.allCases {
			#expect(aqi.id == aqi.rawValue)
		}
	}
}

// MARK: - Iaq

@Suite("Indoor Air Quality")
struct IaqTests {

	@Test func getIaq_excellentRange_returnsExcellent() {
		#expect(Iaq.getIaq(for: 0) == .excellent)
		#expect(Iaq.getIaq(for: 50) == .excellent)
	}

	@Test func getIaq_goodRange_returnsGood() {
		#expect(Iaq.getIaq(for: 51) == .good)
		#expect(Iaq.getIaq(for: 100) == .good)
	}

	@Test func getIaq_lightlyPollutedRange_returnsLightlyPolluted() {
		#expect(Iaq.getIaq(for: 101) == .lightlyPolluted)
		#expect(Iaq.getIaq(for: 150) == .lightlyPolluted)
	}

	@Test func getIaq_moderatelyPollutedRange() {
		#expect(Iaq.getIaq(for: 151) == .moderatelyPolluted)
		#expect(Iaq.getIaq(for: 200) == .moderatelyPolluted)
	}

	@Test func getIaq_heavilyPollutedRange() {
		#expect(Iaq.getIaq(for: 201) == .heavilyPolluted)
		#expect(Iaq.getIaq(for: 250) == .heavilyPolluted)
	}

	@Test func getIaq_severelyPollutedRange() {
		#expect(Iaq.getIaq(for: 251) == .severelyPolluted)
		#expect(Iaq.getIaq(for: 350) == .severelyPolluted)
	}

	@Test func getIaq_extremelyPollutedRange() {
		#expect(Iaq.getIaq(for: 351) == .extremelyPolluted)
		#expect(Iaq.getIaq(for: 1000) == .extremelyPolluted)
	}

	@Test func allCases_haveNonEmptyDescription() {
		for iaq in Iaq.allCases {
			#expect(!iaq.description.isEmpty)
		}
	}

	@Test func allCases_haveColors() {
		#expect(Iaq.excellent.color == .green)
		#expect(Iaq.good.color == .mint)
		#expect(Iaq.extremelyPolluted.color == .brown)
	}

	@Test func allCases_rangesDoNotOverlap() {
		let sorted = Iaq.allCases.sorted { $0.rawValue < $1.rawValue }
		for i in 0..<sorted.count - 1 {
			#expect(sorted[i].range.upperBound <= sorted[i + 1].range.lowerBound,
				"Range overlap between \(sorted[i]) and \(sorted[i + 1])")
		}
	}
}

// MARK: - Tapbacks

@Suite("Tapback Reactions")
struct TapbackTests {

	@Test func allCases_haveNonEmptyEmojiString() {
		for tapback in Tapbacks.allCases {
			#expect(!tapback.emojiString.isEmpty, "Tapback \(tapback) has empty emoji string")
		}
	}

	@Test func allCases_haveNonEmptyDescription() {
		for tapback in Tapbacks.allCases {
			#expect(!tapback.description.isEmpty, "Tapback \(tapback) has empty description")
		}
	}

	@Test func emojiStrings_areUniquePerCase() {
		let emojis = Tapbacks.allCases.map(\.emojiString)
		#expect(Set(emojis).count == emojis.count)
	}

	@Test func wave_hasCorrectEmoji() {
		#expect(Tapbacks.wave.emojiString == "👋")
	}

	@Test func heart_hasCorrectEmoji() {
		#expect(Tapbacks.heart.emojiString == "❤️")
	}

	@Test func thumbsUp_hasCorrectEmoji() {
		#expect(Tapbacks.thumbsUp.emojiString == "👍")
	}

	@Test func poop_hasCorrectEmoji() {
		#expect(Tapbacks.poop.emojiString == "💩")
	}

	@Test func totalCaseCount_isEight() {
		#expect(Tapbacks.allCases.count == 8)
	}
}

// MARK: - MetricsTypes

@Suite("MetricsTypes")
struct MetricsTypesTests {

	@Test func allCases_haveNonEmptyName() {
		for metric in MetricsTypes.allCases {
			#expect(!metric.name.isEmpty)
		}
	}

	@Test func totalCaseCount_isFive() {
		#expect(MetricsTypes.allCases.count == 5)
	}

	@Test func device_isDefaultZero() {
		#expect(MetricsTypes.device.rawValue == 0)
	}
}
