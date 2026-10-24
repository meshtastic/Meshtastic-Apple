//
//  LocalStatsChartTicks.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/20/26.
//

import Foundation

/// One noise floor reading on the local stats chart.
struct LocalStatsChartPoint: Identifiable, Equatable {
	let time: Date
	let noiseFloor: Int32

	var id: Date { time }

	/// How far past now a reading may be stamped and still anchor the chart. A clock this
	/// far fast is usually a node that lost its time sync, and its readings are real; one
	/// further out is a bad timestamp.
	static let fastClockLimit: TimeInterval = 30 * 86_400

	/// How far back from the newest drawn reading the chart reaches. The chart holds
	/// at most 500 rows, so a year never hides real history.
	static let historyLimit: TimeInterval = 365 * 86_400

	/// The readings the chart draws, oldest first, from `readings` newest first as the
	/// fetch returns them. A node with a wrong clock stamps readings in the future or in
	/// 1970, and either stretches the scrollable range by years. The newest reading no
	/// more than 30 days past `now` anchors the chart, and readings past it, or more than
	/// a year older, stay off. When every reading is further out than that, the node's
	/// clock is simply wrong and its readings are still real, so the newest one anchors
	/// instead and the chart draws them rather than going blank above a full table; the
	/// year window keeps the span bounded either way. One reading per timestamp, since
	/// the chart keys its marks on the time. The table and CSV keep every row.
	static func plottable(_ readings: [LocalStatsChartPoint], now: Date) -> [LocalStatsChartPoint] {
		let latest = now.addingTimeInterval(fastClockLimit)
		guard let newest = (readings.first(where: { $0.time <= latest }) ?? readings.first)?.time else { return [] }
		let window = newest.addingTimeInterval(-historyLimit)...newest
		var seen = Set<Date>()
		return readings.filter { window.contains($0.time) && seen.insert($0.time).inserted }.reversed()
	}
}

/// X-axis ticks for the scrolling noise floor chart. With `.automatic` values Charts
/// built marks across the whole scrollable range, so weeks of readings, or one reading
/// with a wrong clock, froze the app on the 1h view. These cover the visible window
/// plus one window either side and nothing more.
enum LocalStatsChartTicks {

	/// Hard cap on the ticks handed to the axis, whatever the inputs.
	static let maxCount = 64

	/// Round tick spacings in seconds: minutes, hours, days, one and two weeks, then 30,
	/// 90, 180 and 365 days. The day steps count from the 2001 reference date, so a
	/// 30-day tick is not a month start.
	static let steps: [TimeInterval] = [
		5 * 60, 10 * 60, 15 * 60, 30 * 60,
		60 * 60, 2 * 60 * 60, 3 * 60 * 60, 6 * 60 * 60, 12 * 60 * 60,
		86_400, 2 * 86_400, 3 * 86_400, 7 * 86_400, 14 * 86_400,
		30 * 86_400, 90 * 86_400, 180 * 86_400, 365 * 86_400
	]

	/// The largest round step that fits `labelCount` ticks in the visible window, so a
	/// window never shows fewer labels than asked for. The smallest step is the floor.
	static func step(visible: TimeInterval, labelCount: Int) -> TimeInterval {
		let target = visible / Double(max(labelCount, 1))
		return steps.last(where: { $0 <= target }) ?? steps[0]
	}

	/// `date` rounded down to a multiple of `step`. The chart keys its tick update on
	/// this, so scrolling within one step changes nothing.
	static func quantize(_ date: Date, step: TimeInterval) -> Date {
		Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded(.down) * step)
	}

	/// Tick dates for the window one visible span either side of `scrollPosition`,
	/// clamped to the data so explicit axis values never widen the scrollable range.
	/// Ticks sit on round local times (midnight, round hours) on both sides of a
	/// daylight saving change.
	static func ticks(visible: TimeInterval, labelCount: Int, scrollPosition: Date, dataRange: ClosedRange<Date>, timeZone: TimeZone) -> [Date] {
		let step = step(visible: visible, labelCount: labelCount)
		let position = quantize(scrollPosition, step: step)
		let lower = max(position.addingTimeInterval(-visible), dataRange.lowerBound)
		// Data shorter than the window still fills a window's width on screen.
		let dataEnd = max(dataRange.upperBound, dataRange.lowerBound.addingTimeInterval(visible))
		let upper = min(position.addingTimeInterval(2 * visible), dataEnd)
		guard lower <= upper else { return [] }

		var ticks: [Date] = []
		var wallClock = (wallClock(of: lower, in: timeZone) / step).rounded(.up) * step
		while ticks.count < maxCount {
			let tick = date(atWallClock: wallClock, in: timeZone)
			if tick > upper { break }
			// A tick in the hour a spring-forward skips lands on the one before it.
			if tick >= lower, tick > ticks.last ?? .distantPast {
				ticks.append(tick)
			}
			wallClock += step
		}
		return ticks
	}

	/// Seconds since the reference date as the local clock shows them.
	private static func wallClock(of date: Date, in timeZone: TimeZone) -> TimeInterval {
		date.timeIntervalSinceReferenceDate + TimeInterval(timeZone.secondsFromGMT(for: date))
	}

	/// The instant at which the local clock reads `wallClock`. The offset depends on
	/// the instant, so take it at a first guess and again at the result; that lands
	/// on round local times either side of a daylight saving change.
	private static func date(atWallClock wallClock: TimeInterval, in timeZone: TimeZone) -> Date {
		let guessOffset = timeZone.secondsFromGMT(for: Date(timeIntervalSinceReferenceDate: wallClock))
		let guess = Date(timeIntervalSinceReferenceDate: wallClock - TimeInterval(guessOffset))
		return Date(timeIntervalSinceReferenceDate: wallClock - TimeInterval(timeZone.secondsFromGMT(for: guess)))
	}
}
