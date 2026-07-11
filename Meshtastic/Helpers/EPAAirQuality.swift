//
//  EPAAirQuality.swift
//  Meshtastic
//
//  US EPA air quality math for PM2.5 (issue #2040 / design#54):
//   • NowCast — a 12-hour weighted rolling average that favors recent hours.
//   • AQI — the 0–500 index derived from a PM2.5 concentration via EPA Equation 1.
//
//  References:
//   • EPA/AirNow "Technical Assistance Document for the Reporting of Daily Air Quality"
//     (Equation 1, truncation + rounding rules, NowCast data-sufficiency rule).
//   • EPA AQS breakpoint code table (parameter 88101, PM2.5 24-hour), current
//     post-2024 concentration breakpoints.
//

import Foundation

enum EPAAirQuality {

	/// One row of the EPA AQI breakpoint table: a concentration range (µg/m³) mapped to an AQI range.
	struct PM25Breakpoint {
		let concentrationLow: Double
		let concentrationHigh: Double
		let aqiLow: Int
		let aqiHigh: Int
	}

	/// Current (2024) EPA PM2.5 24-hour AQI breakpoints (µg/m³ → AQI index).
	/// Contiguous at 0.1 µg/m³ resolution; concentrations are truncated to one decimal
	/// place before lookup so the 0.1 gaps between rows (e.g. 9.0 / 9.1) never fall through.
	/// The app's `Aqi` scale tops out at 500, so concentrations above the final breakpoint
	/// clamp to 500 rather than extending into the 501–999 "beyond the AQI" range.
	static let pm25Breakpoints: [PM25Breakpoint] = [
		PM25Breakpoint(concentrationLow: 0.0, concentrationHigh: 9.0, aqiLow: 0, aqiHigh: 50),
		PM25Breakpoint(concentrationLow: 9.1, concentrationHigh: 35.4, aqiLow: 51, aqiHigh: 100),
		PM25Breakpoint(concentrationLow: 35.5, concentrationHigh: 55.4, aqiLow: 101, aqiHigh: 150),
		PM25Breakpoint(concentrationLow: 55.5, concentrationHigh: 125.4, aqiLow: 151, aqiHigh: 200),
		PM25Breakpoint(concentrationLow: 125.5, concentrationHigh: 225.4, aqiLow: 201, aqiHigh: 300),
		PM25Breakpoint(concentrationLow: 225.5, concentrationHigh: 325.4, aqiLow: 301, aqiHigh: 500)
	]

	/// Minimum weight factor for the PM NowCast; approximates a 3-hour average when
	/// pollutant levels are changing rapidly.
	static let nowCastMinimumWeight = 0.5

	/// AQI (0–500) from a PM2.5 concentration (µg/m³) using EPA Equation 1:
	///   I = (Ihi − Ilo) / (BPhi − BPlo) · (C − BPlo) + Ilo
	/// The concentration is truncated to one decimal place; the result is rounded to the
	/// nearest integer. Returns `nil` for negative input.
	static func aqi(fromPM25 concentration: Double) -> Int? {
		guard concentration >= 0 else { return nil }
		// Truncate to one decimal place (EPA rule for PM2.5). Direct sensor readings are integer
		// µg/m³ (Stage 1 stores pm25Standard as UInt32) so they truncate exactly; NowCast averages
		// are fractional, where an exact-boundary hit is measure-zero and at most ±1 AQI. `.towardZero`
		// == floor here because the value is already guarded non-negative.
		let c = (concentration * 10).rounded(.towardZero) / 10.0
		for bp in pm25Breakpoints where c <= bp.concentrationHigh {
			let slope = Double(bp.aqiHigh - bp.aqiLow) / (bp.concentrationHigh - bp.concentrationLow)
			let index = slope * (c - bp.concentrationLow) + Double(bp.aqiLow)
			return min(500, max(0, Int(index.rounded())))
		}
		// Above the top breakpoint: clamp to the ceiling of the app's AQI scale.
		return 500
	}

	/// EPA NowCast for PM2.5 from up to 12 hourly averages.
	/// `hourly[0]` is the most recent clock hour, `hourly[11]` is 11 hours earlier; `nil`
	/// marks a missing hour. Returns `nil` when there isn't enough recent data — EPA requires
	/// at least two of the three most recent hours to be valid.
	static func nowCastPM25(hourly: [Double?]) -> Double? {
		let hours = Array(hourly.prefix(12))
		// Data sufficiency: 2 of the 3 most recent hours must be present.
		guard hours.prefix(3).compactMap({ $0 }).count >= 2 else { return nil }

		let valid = hours.compactMap { $0 }
		guard let cMax = valid.max(), let cMin = valid.min() else { return nil }
		// If the max is 0 every reading is 0 → NowCast is 0 (avoids divide-by-zero on the weight).
		guard cMax > 0 else { return 0 }

		// Weight factor = 1 − (scaled rate of change), floored at the minimum weight.
		let weightFactor = max(cMin / cMax, nowCastMinimumWeight)

		var numerator = 0.0
		var denominator = 0.0
		for (hoursAgo, value) in hours.enumerated() {
			guard let concentration = value else { continue }
			let weight = pow(weightFactor, Double(hoursAgo))
			numerator += weight * concentration
			denominator += weight
		}
		guard denominator > 0 else { return nil }
		return numerator / denominator
	}

	/// Buckets timestamped PM2.5 readings into the most recent 12 clock hours, computes the
	/// NowCast, and maps it to an AQI (0–500). Returns `nil` when NowCast can't be computed
	/// (insufficient recent history) — callers should fall back to showing the raw reading.
	static func nowCastAQI(
		from readings: [(date: Date, pm25: Double)],
		now: Date = Date(),
		calendar: Calendar = .current
	) -> Int? {
		guard !readings.isEmpty else { return nil }
		let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now

		var buckets: [Int: (sum: Double, count: Int)] = [:]
		for reading in readings {
			guard let hourStart = calendar.dateInterval(of: .hour, for: reading.date)?.start else { continue }
			guard let hoursAgo = calendar.dateComponents([.hour], from: hourStart, to: currentHourStart).hour else { continue }
			guard hoursAgo >= 0, hoursAgo < 12 else { continue }
			var bucket = buckets[hoursAgo] ?? (sum: 0, count: 0)
			bucket.sum += reading.pm25
			bucket.count += 1
			buckets[hoursAgo] = bucket
		}

		let hourly: [Double?] = (0..<12).map { hoursAgo in
			guard let bucket = buckets[hoursAgo], bucket.count > 0 else { return nil }
			return bucket.sum / Double(bucket.count)
		}

		guard let nowCast = nowCastPM25(hourly: hourly) else { return nil }
		return aqi(fromPM25: nowCast)
	}
}
