//
//  AirQualityCalculator.swift
//  Meshtastic
//
//  EPA NowCast + AQI breakpoint math for PM2.5, per meshtastic/design#54.
//
//  Ported from the Android reference implementation (Meshtastic-Android PR #6102) so both
//  platforms compute identical AQI values from the same PM2.5 history.
//
//  NowCast is a 12-hour rolling average of PM2.5 that weights recent hours more heavily than
//  older ones. It is used in lieu of the official 24h EPA AQI average because it can report a
//  value well before a full day of data exists — while still refusing to report a misleading
//  instantaneous value when there isn't enough recent history.
//  See https://www.airnow.gov (NowCast) and the EPA PM2.5 AQI breakpoint table.
//

import Foundation

enum AirQualityCalculator {

	private static let nowCastWindowHours = 12
	private static let secondsPerHour: TimeInterval = 3600
	/// EPA requires the most recent hour plus at least 2 of the 3 most recent hours, or NowCast isn't reported.
	private static let minValidHours = 2
	private static let recentWindowHours = 3
	private static let minWeightFactor = 0.5

	/// Computes the NowCast PM2.5 concentration (µg/m³) from a node's PM2.5 `readings`
	/// (epoch-seconds → µg/m³), relative to `nowEpochSeconds`. Readings are binned into hourly
	/// buckets (0 = most recent hour) and averaged within each bucket.
	///
	/// Returns `nil` if there isn't enough history yet: the most recent hour must have a reading,
	/// and at least `minValidHours` of the `recentWindowHours` most recent hours must be populated
	/// (EPA's minimum-data rule) — so stale data spread across the older end of the 12h window can't
	/// produce a value. Callers should fall back to showing the raw latest reading in that case.
	static func computeNowCastPm25(readings: [(time: TimeInterval, pm25: Double)], nowEpochSeconds: TimeInterval) -> Double? {
		var sums = [Double](repeating: 0, count: nowCastWindowHours)
		var counts = [Int](repeating: 0, count: nowCastWindowHours)
		for reading in readings {
			let hoursAgo = Int((nowEpochSeconds - reading.time) / secondsPerHour)
			if hoursAgo >= 0 && hoursAgo < nowCastWindowHours {
				sums[hoursAgo] += reading.pm25
				counts[hoursAgo] += 1
			}
		}
		let hourlyAverages: [Double?] = (0..<nowCastWindowHours).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
		let present: [(hoursAgo: Int, value: Double)] = hourlyAverages.enumerated().compactMap { index, value in
			value.map { (index, $0) }
		}

		let recentValid = hourlyAverages.prefix(recentWindowHours).filter { $0 != nil }.count
		guard hourlyAverages[0] != nil, recentValid >= minValidHours else {
			return nil
		}

		let maxValue = present.map { $0.value }.max() ?? 0
		let minValue = present.map { $0.value }.min() ?? 0
		let weightFactor = maxValue <= 0 ? 1.0 : max(1.0 - (maxValue - minValue) / maxValue, minWeightFactor)

		var weightedSum = 0.0
		var weightTotal = 0.0
		for entry in present {
			let weight = pow(weightFactor, Double(entry.hoursAgo))
			weightedSum += weight * entry.value
			weightTotal += weight
		}
		return weightedSum / weightTotal
	}

	private struct Breakpoint {
		let concentrationLow: Double
		let concentrationHigh: Double
		let aqiLow: Int
		let aqiHigh: Int
	}

	// Standard EPA PM2.5 (µg/m³) breakpoint table.
	private static let breakpoints: [Breakpoint] = [
		Breakpoint(concentrationLow: 0.0, concentrationHigh: 12.0, aqiLow: 0, aqiHigh: 50),
		Breakpoint(concentrationLow: 12.1, concentrationHigh: 35.4, aqiLow: 51, aqiHigh: 100),
		Breakpoint(concentrationLow: 35.5, concentrationHigh: 55.4, aqiLow: 101, aqiHigh: 150),
		Breakpoint(concentrationLow: 55.5, concentrationHigh: 150.4, aqiLow: 151, aqiHigh: 200),
		Breakpoint(concentrationLow: 150.5, concentrationHigh: 250.4, aqiLow: 201, aqiHigh: 300),
		Breakpoint(concentrationLow: 250.5, concentrationHigh: 500.4, aqiLow: 301, aqiHigh: 500)
	]

	/// Converts a PM2.5 concentration (µg/m³) to a 0–500 EPA AQI value via linear interpolation over
	/// the standard breakpoint table. Negative inputs clamp to 0; concentrations above the top
	/// breakpoint clamp to AQI 500. The result is always in `0...500`, safe to pass to `Aqi.getAqi(for:)`.
	static func pm25ToAqi(_ concentration: Double) -> Int {
		let clamped = max(concentration, 0)
		let breakpoint = breakpoints.last(where: { clamped >= $0.concentrationLow }) ?? breakpoints[0]
		if clamped > breakpoint.concentrationHigh { return breakpoint.aqiHigh }
		let aqi = Double(breakpoint.aqiHigh - breakpoint.aqiLow) /
			(breakpoint.concentrationHigh - breakpoint.concentrationLow) *
			(clamped - breakpoint.concentrationLow) + Double(breakpoint.aqiLow)
		return Int(aqi.rounded())
	}
}
