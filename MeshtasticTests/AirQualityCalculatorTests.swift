//
//  AirQualityCalculatorTests.swift
//  MeshtasticTests
//
//  Verifies the EPA NowCast + AQI breakpoint math (meshtastic/design#54). Expected values mirror
//  the Android reference test (Meshtastic-Android AirQualityIndexTest) so both platforms stay aligned.
//

import XCTest
@testable import Meshtastic

final class AirQualityCalculatorTests: XCTestCase {

	private let secondsPerHour: TimeInterval = 3600
	private let now: TimeInterval = 1_000_000
	private let epsilon = 0.001

	// MARK: - pm25ToAqi

	func testPm25ToAqiMatchesEpaBreakpointTable() {
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(0.0), 0)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(12.0), 50)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(12.1), 51)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(35.4), 100)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(35.5), 101)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(55.4), 150)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(55.5), 151)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(150.4), 200)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(150.5), 201)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(250.4), 300)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(250.5), 301)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(500.4), 500)
	}

	func testPm25ToAqiClampsNegativeAndAboveScale() {
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(-5.0), 0)
		XCTAssertEqual(AirQualityCalculator.pm25ToAqi(1000.0), 500)
	}

	// MARK: - computeNowCastPm25

	func testReturnsNilWhenMostRecentHourMissing() {
		// Only hour 1 (an hour ago) has data — EPA requires the most recent hour to be present.
		let readings = [(time: now - secondsPerHour, pm25: 20.0)]
		XCTAssertNil(AirQualityCalculator.computeNowCastPm25(readings: readings, nowEpochSeconds: now))
	}

	func testReturnsNilWithFewerThanTwoValidHours() {
		let readings = [(time: now, pm25: 20.0)]
		XCTAssertNil(AirQualityCalculator.computeNowCastPm25(readings: readings, nowEpochSeconds: now))
	}

	func testReturnsNilWhenSecondValidHourOutsideRecentThree() {
		// Two valid hours in the 12h window (now + 11h ago), but only one within the most recent 3.
		let readings = [(time: now, pm25: 20.0), (time: now - 11 * secondsPerHour, pm25: 20.0)]
		XCTAssertNil(AirQualityCalculator.computeNowCastPm25(readings: readings, nowEpochSeconds: now))
	}

	func testAveragesStableReadingsWithWeightFactorOne() {
		let readings = [
			(time: now, pm25: 20.0),
			(time: now - secondsPerHour, pm25: 20.0),
			(time: now - 2 * secondsPerHour, pm25: 20.0)
		]
		let result = AirQualityCalculator.computeNowCastPm25(readings: readings, nowEpochSeconds: now)
		XCTAssertEqual(try XCTUnwrap(result), 20.0, accuracy: epsilon)
	}

	func testWeightsRecentHoursMoreHeavilyWhenDeclining() {
		// c1=20 (now), c2=10 (1h ago). weightFactor = 1 - (20-10)/20 = 0.5. NowCast = (20*1 + 10*0.5)/(1+0.5).
		let readings = [(time: now, pm25: 20.0), (time: now - secondsPerHour, pm25: 10.0)]
		let result = AirQualityCalculator.computeNowCastPm25(readings: readings, nowEpochSeconds: now)
		XCTAssertEqual(try XCTUnwrap(result), 25.0 / 1.5, accuracy: epsilon)
	}

	func testAppliesMinimumWeightFactorFloor() {
		// Range far exceeds max, so the raw weight factor would go negative — it must floor at 0.5.
		let readings = [(time: now, pm25: 100.0), (time: now - secondsPerHour, pm25: 1.0)]
		let result = AirQualityCalculator.computeNowCastPm25(readings: readings, nowEpochSeconds: now)
		XCTAssertEqual(try XCTUnwrap(result), 100.5 / 1.5, accuracy: epsilon)
	}

	func testAveragesMultipleReadingsWithinSameHour() {
		let readings = [
			(time: now, pm25: 10.0),
			(time: now - 60, pm25: 30.0), // same hour bucket -> averages to 20.0
			(time: now - secondsPerHour, pm25: 20.0)
		]
		let result = AirQualityCalculator.computeNowCastPm25(readings: readings, nowEpochSeconds: now)
		XCTAssertEqual(try XCTUnwrap(result), 20.0, accuracy: epsilon)
	}

	func testIgnoresReadingsOlderThanTwelveHourWindow() {
		let readings = [
			(time: now, pm25: 20.0),
			(time: now - secondsPerHour, pm25: 20.0),
			(time: now - 13 * secondsPerHour, pm25: 500.0)
		]
		let result = AirQualityCalculator.computeNowCastPm25(readings: readings, nowEpochSeconds: now)
		XCTAssertEqual(try XCTUnwrap(result), 20.0, accuracy: epsilon)
	}
}
