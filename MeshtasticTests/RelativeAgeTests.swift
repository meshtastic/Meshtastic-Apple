//
//  RelativeAgeTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/19/26.
//

import Testing
import Foundation

/// `RelativeAge` is in the tvOS target, which has no test target of its own, so the
/// rule is duplicated here to pin the behaviour that matters: a just-arrived sample
/// must never read as future tense.
@Suite("Relative age")
struct RelativeAgeTests {

	private func text(since date: Date, now: Date) -> String {
		let elapsed = max(0, now.timeIntervalSince(date))
		if elapsed < 60 { return "\(Int(elapsed))s ago" }
		return date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
	}

	@Test func justArrivedReadsAsPast() {
		let now = Date(timeIntervalSince1970: 1_000_000)
		// The bug: Foundation renders this as "in 0 sec.".
		#expect(text(since: now, now: now) == "0s ago")
		#expect(text(since: now.addingTimeInterval(-0.4), now: now) == "0s ago")
	}

	@Test func subMinuteCountsSeconds() {
		let now = Date(timeIntervalSince1970: 2_000_000)
		#expect(text(since: now.addingTimeInterval(-12), now: now) == "12s ago")
		#expect(text(since: now.addingTimeInterval(-59), now: now) == "59s ago")
	}

	@Test func aFutureStampNeverGoesNegative() {
		let now = Date(timeIntervalSince1970: 3_000_000)
		// Clock skew between radio and phone must not produce "-5s ago".
		#expect(text(since: now.addingTimeInterval(5), now: now) == "0s ago")
	}

	@Test func pastAMinuteHandsOffToTheFormatter() {
		let now = Date(timeIntervalSince1970: 4_000_000)
		let result = text(since: now.addingTimeInterval(-600), now: now)
		#expect(!result.hasSuffix("s ago") || result.contains("min"))
		#expect(!result.contains("in "), "must not be future tense, got \(result)")
	}
}
