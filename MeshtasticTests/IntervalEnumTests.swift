import Foundation
import Testing

@testable import Meshtastic

// MARK: - IntervalConfiguration

@Suite("IntervalConfiguration")
struct IntervalConfigurationTests {

	@Test func all_containsAllFixedCases() {
		let allowed = IntervalConfiguration.all.allowedCases
		#expect(allowed.count == FixedUpdateIntervals.allCases.count)
	}

	@Test func broadcastShort_startsWithUnset() {
		let cases = IntervalConfiguration.broadcastShort.allowedCases
		#expect(cases.first == .unset)
	}

	@Test func broadcastShort_containsNever() {
		let cases = IntervalConfiguration.broadcastShort.allowedCases
		#expect(cases.contains(.never))
	}

	@Test func broadcastMedium_startsWithOneHour() {
		let cases = IntervalConfiguration.broadcastMedium.allowedCases
		#expect(cases.first == .oneHour)
	}

	@Test func broadcastLong_startsWithThreeHours() {
		let cases = IntervalConfiguration.broadcastLong.allowedCases
		#expect(cases.first == .threeHours)
	}

	@Test func nagTimeout_containsOneSecond() {
		let cases = IntervalConfiguration.nagTimeout.allowedCases
		#expect(cases.contains(.oneSecond))
	}

	@Test func rangeTestSender_containsFifteenSeconds() {
		let cases = IntervalConfiguration.rangeTestSender.allowedCases
		#expect(cases.contains(.fifteenSeconds))
	}

	@Test func allConfigurations_haveNonEmptyAllowedCases() {
		for config in IntervalConfiguration.allCases {
			#expect(!config.allowedCases.isEmpty, "\(config) has empty allowed cases")
		}
	}
}

// MARK: - FixedUpdateIntervals

@Suite("FixedUpdateIntervals")
struct FixedUpdateIntervalsTests {

	@Test func totalCaseCount() {
		#expect(FixedUpdateIntervals.allCases.count == 26)
	}

	@Test func unset_isZero() {
		#expect(FixedUpdateIntervals.unset.rawValue == 0)
	}

	@Test func never_isMaxInt() {
		#expect(FixedUpdateIntervals.never.rawValue == 2147483647)
	}

	@Test func oneHour_is3600() {
		#expect(FixedUpdateIntervals.oneHour.rawValue == 3600)
	}

	@Test func allCases_haveUniqueRawValues() {
		let rawValues = FixedUpdateIntervals.allCases.map(\.rawValue)
		#expect(Set(rawValues).count == rawValues.count)
	}
}

// MARK: - UpdateInterval

@Suite("UpdateInterval")
struct UpdateIntervalTests {

	@Test func initFromKnownValue_createsFixed() {
		let interval = UpdateInterval(from: 3600)
		if case .fixed(let fixed) = interval.type {
			#expect(fixed == .oneHour)
		} else {
			#expect(Bool(false), "Expected fixed type")
		}
	}

	@Test func initFromUnknownValue_createsManual() {
		let interval = UpdateInterval(from: 42)
		if case .manual(let value) = interval.type {
			#expect(value == 42)
		} else {
			#expect(Bool(false), "Expected manual type")
		}
	}

	@Test func intValue_fixedReturnsRawValue() {
		let interval = UpdateInterval(from: 60)
		#expect(interval.intValue == 60)
	}

	@Test func intValue_manualReturnsCustomValue() {
		let interval = UpdateInterval(from: 999)
		#expect(interval.intValue == 999)
	}

	@Test func description_fixedHasHumanReadable() {
		let interval = UpdateInterval(from: 3600)
		#expect(!interval.description.isEmpty)
	}

	@Test func description_manualContainsCustom() {
		let interval = UpdateInterval(from: 42)
		#expect(interval.description.contains("42"))
	}

	@Test func id_fixedStartsWithFixed() {
		let interval = UpdateInterval(from: 60)
		#expect(interval.id.hasPrefix("fixed_"))
	}

	@Test func id_manualStartsWithManual() {
		let interval = UpdateInterval(from: 42)
		#expect(interval.id.hasPrefix("manual_"))
	}

	@Test func allFixedCases_haveNonEmptyDescription() {
		for fixed in FixedUpdateIntervals.allCases {
			let interval = UpdateInterval(from: fixed.rawValue)
			#expect(!interval.description.isEmpty, "UpdateInterval for \(fixed) has empty description")
		}
	}

	@Test func hashable_sameValuesEqual() {
		let a = UpdateInterval(from: 300)
		let b = UpdateInterval(from: 300)
		#expect(a == b)
	}

	@Test func hashable_differentValuesNotEqual() {
		let a = UpdateInterval(from: 300)
		let b = UpdateInterval(from: 600)
		#expect(a != b)
	}
}

// MARK: - OutputIntervals

@Suite("OutputIntervals")
struct OutputIntervalsTests {

	@Test func allCases_haveNonEmptyDescription() {
		for interval in OutputIntervals.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(OutputIntervals.allCases.count == 10)
	}

	@Test func unset_isZero() {
		#expect(OutputIntervals.unset.rawValue == 0)
	}

	@Test func oneMinute_is60000() {
		#expect(OutputIntervals.oneMinute.rawValue == 60000)
	}
}
