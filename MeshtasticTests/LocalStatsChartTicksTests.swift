//
//  LocalStatsChartTicksTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/20/26.
//

import Foundation
import Testing
@testable import Meshtastic

@Suite("Local stats chart ticks")
struct LocalStatsChartTicksTests {

	private let utc = TimeZone(identifier: "UTC")!
	private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
	private let hour: TimeInterval = 60 * 60
	private let day: TimeInterval = 24 * 60 * 60
	/// The chart never shows less than this, however little data there is.
	private let minimumVisible: TimeInterval = 15 * 60

	private func date(_ iso: String) -> Date {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime]
		return formatter.date(from: iso)!
	}

	private func localComponents(_ date: Date, in zone: TimeZone) -> DateComponents {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = zone
		return calendar.dateComponents([.hour, .minute], from: date)
	}

	@Test("Never more than the cap, whatever the inputs")
	func capped() {
		let first = date("2026-01-01T00:00:00Z")
		let ticks = LocalStatsChartTicks.ticks(
			visible: day, labelCount: 200, scrollPosition: first.addingTimeInterval(10 * day),
			dataRange: first...first.addingTimeInterval(30 * day), timeZone: utc
		)
		#expect(ticks.count == LocalStatsChartTicks.maxCount)
	}

	@Test("Step is always a round one, never the raw window split")
	func stepIsRound() {
		for visible in [900.0, hour, 6 * hour, day, 7 * day, 16 * day, 30 * day, 200 * day, 365 * day] {
			for labelCount in [2, 6] {
				let step = LocalStatsChartTicks.step(visible: visible, labelCount: labelCount)
				#expect(LocalStatsChartTicks.steps.contains(step), "visible \(visible) labels \(labelCount)")
				#expect(step <= max(visible / Double(labelCount), LocalStatsChartTicks.steps[0]))
			}
		}
	}

	@Test("A 7d window on a phone holds at least two ticks")
	func weekOnCompactWidth() {
		let last = date("2026-06-15T13:37:00Z")
		let first = last.addingTimeInterval(-30 * day)
		let position = last.addingTimeInterval(-7 * day)
		let ticks = LocalStatsChartTicks.ticks(
			visible: 7 * day, labelCount: 2, scrollPosition: position, dataRange: first...last, timeZone: utc
		)
		let onScreen = ticks.filter { (position...last).contains($0) }
		#expect(onScreen.count >= 2)
	}

	@Test("The All window on a phone holds at least two ticks for any history length")
	func allOnCompactWidth() {
		let first = date("2026-01-10T05:00:00Z")
		for span in [900.0, 2 * hour, day, 8 * day, 16 * day, 45 * day, 100 * day, 200 * day, 365 * day] {
			let last = first.addingTimeInterval(span)
			let visible = max(span, minimumVisible)
			let ticks = LocalStatsChartTicks.ticks(
				visible: visible, labelCount: 2, scrollPosition: first, dataRange: first...last, timeZone: utc
			)
			#expect(ticks.count >= 2, "span \(span / day) days gave \(ticks.count) ticks")
			#expect(ticks.allSatisfy { (first...last.addingTimeInterval(visible)).contains($0) })
		}
	}

	@Test("Ticks never reach past the data on either side")
	func clampedToData() {
		let last = date("2026-06-15T13:37:00Z")
		let first = last.addingTimeInterval(-30 * day)
		let atEnd = LocalStatsChartTicks.ticks(
			visible: hour, labelCount: 2, scrollPosition: last.addingTimeInterval(-hour), dataRange: first...last, timeZone: utc
		)
		#expect(!atEnd.isEmpty)
		#expect(atEnd.allSatisfy { $0 <= last })
		#expect(atEnd.allSatisfy { $0 >= last.addingTimeInterval(-3 * hour) })

		let atStart = LocalStatsChartTicks.ticks(
			visible: hour, labelCount: 2, scrollPosition: first, dataRange: first...last, timeZone: utc
		)
		#expect(!atStart.isEmpty)
		#expect(atStart.allSatisfy { $0 >= first })
		#expect(atStart.allSatisfy { $0 <= first.addingTimeInterval(3 * hour) })
	}

	@Test("A single reading still gets ticks across its window")
	func singleReading() {
		let only = date("2026-06-15T13:37:00Z")
		let ticks = LocalStatsChartTicks.ticks(
			visible: minimumVisible, labelCount: 2, scrollPosition: only,
			dataRange: only...only, timeZone: utc
		)
		#expect(ticks.count >= 2)
	}

	@Test("Scrolling within a step keeps the same ticks; crossing a step boundary changes them")
	func quantized() {
		let first = date("2026-06-01T00:00:00Z")
		let last = first.addingTimeInterval(30 * day)
		let step = LocalStatsChartTicks.step(visible: hour, labelCount: 2)
		#expect(step == 30 * 60)
		let position = first.addingTimeInterval(10 * day)
		func ticks(at offset: TimeInterval) -> [Date] {
			LocalStatsChartTicks.ticks(
				visible: hour, labelCount: 2, scrollPosition: position.addingTimeInterval(offset),
				dataRange: first...last, timeZone: utc
			)
		}
		#expect(ticks(at: 0) == ticks(at: step - 1))
		#expect(ticks(at: 0) != ticks(at: step))
		#expect(LocalStatsChartTicks.quantize(position.addingTimeInterval(step - 1), step: step) == position)
	}

	@Test("Quantize rounds down before the 2001 reference date too")
	func quantizeBeforeReferenceDate() {
		let epoch = Date(timeIntervalSince1970: 0)
		let step: TimeInterval = 30 * 60
		#expect(epoch.timeIntervalSinceReferenceDate < 0)
		#expect(LocalStatsChartTicks.quantize(epoch, step: step) == epoch)
		#expect(LocalStatsChartTicks.quantize(epoch.addingTimeInterval(1000), step: step) == epoch)
		#expect(LocalStatsChartTicks.quantize(epoch.addingTimeInterval(-1), step: step) == epoch.addingTimeInterval(-step))

		let ticks = LocalStatsChartTicks.ticks(
			visible: hour, labelCount: 2, scrollPosition: epoch.addingTimeInterval(1000),
			dataRange: epoch...epoch.addingTimeInterval(30 * day), timeZone: utc
		)
		#expect(ticks.first == epoch)
		#expect(ticks.count == 5)
	}

	@Test("A window starting just below a step boundary still holds its labels, with a tick either side")
	func labelsJustBelowStepBoundary() {
		let first = date("2026-06-01T00:00:00Z")
		let last = first.addingTimeInterval(30 * day)
		for visible in [hour, 6 * hour, day] {
			for labelCount in [2, 6] {
				let step = LocalStatsChartTicks.step(visible: visible, labelCount: labelCount)
				// One second short of a boundary, so the rounded position sits a whole
				// step behind where the window starts.
				let position = first.addingTimeInterval(10 * day + step - 1)
				let ticks = LocalStatsChartTicks.ticks(
					visible: visible, labelCount: labelCount, scrollPosition: position,
					dataRange: first...last, timeZone: utc
				)
				let windowEnd = position.addingTimeInterval(visible)
				let onScreen = ticks.filter { (position...windowEnd).contains($0) }
				#expect(onScreen.count >= labelCount, "visible \(visible) labels \(labelCount)")
				guard let firstTick = ticks.first, let lastTick = ticks.last else {
					Issue.record("no ticks for visible \(visible) labels \(labelCount)")
					continue
				}
				#expect(firstTick < position, "visible \(visible) labels \(labelCount)")
				#expect(lastTick > windowEnd, "visible \(visible) labels \(labelCount)")
			}
		}
	}

	@Test("Daily ticks land on local midnight on both sides of a spring-forward change")
	func dailyTicksAcrossSpringForward() {
		let first = date("2026-03-01T00:00:00Z")
		let last = date("2026-03-20T00:00:00Z")
		let ticks = LocalStatsChartTicks.ticks(
			visible: 7 * day, labelCount: 6, scrollPosition: date("2026-03-05T12:00:00Z"),
			dataRange: first...last, timeZone: losAngeles
		)
		#expect(ticks.count == 18)
		#expect(ticks.first == date("2026-03-01T08:00:00Z"))
		#expect(ticks.last == date("2026-03-18T07:00:00Z"))
		for tick in ticks {
			let components = localComponents(tick, in: losAngeles)
			#expect(components.hour == 0 && components.minute == 0, "\(tick)")
		}
		let gaps = zip(ticks.dropFirst(), ticks).map { $0.timeIntervalSince($1) }
		#expect(gaps.filter { $0 == 23 * hour }.count == 1)
		#expect(gaps.allSatisfy { $0 == 23 * hour || $0 == day })
	}

	@Test("Hourly ticks skip the hour a spring-forward removes and never repeat")
	func hourlyTicksAcrossSpringForward() {
		let first = date("2026-03-01T00:00:00Z")
		let last = date("2026-03-20T00:00:00Z")
		let ticks = LocalStatsChartTicks.ticks(
			visible: 6 * hour, labelCount: 6, scrollPosition: date("2026-03-08T09:00:00Z"),
			dataRange: first...last, timeZone: losAngeles
		)
		#expect(ticks.count == 19)
		#expect(ticks.first == date("2026-03-08T03:00:00Z"))
		#expect(ticks.last == date("2026-03-08T21:00:00Z"))
		let gaps = zip(ticks.dropFirst(), ticks).map { $0.timeIntervalSince($1) }
		#expect(gaps.allSatisfy { $0 == hour })
		#expect(ticks.allSatisfy { localComponents($0, in: losAngeles).minute == 0 })
		#expect(!ticks.contains { localComponents($0, in: losAngeles).hour == 2 })
	}

	@Test("Hourly ticks across a fall-back change stay on round local hours and increase")
	func hourlyTicksAcrossFallBack() {
		let first = date("2026-10-20T00:00:00Z")
		let last = date("2026-11-10T00:00:00Z")
		let ticks = LocalStatsChartTicks.ticks(
			visible: 6 * hour, labelCount: 6, scrollPosition: date("2026-11-01T07:00:00Z"),
			dataRange: first...last, timeZone: losAngeles
		)
		#expect(ticks.first == date("2026-11-01T01:00:00Z"))
		#expect(ticks.last == date("2026-11-01T19:00:00Z"))
		let gaps = zip(ticks.dropFirst(), ticks).map { $0.timeIntervalSince($1) }
		#expect(gaps.allSatisfy { $0 > 0 })
		#expect(ticks.allSatisfy { localComponents($0, in: losAngeles).minute == 0 })
		#expect(ticks == ticks.sorted())
		#expect(Set(ticks).count == ticks.count)
	}

	@Test("Ticks sit on round local times in a zone that is not a whole hour from UTC")
	func nonWholeHourZone() {
		let kathmandu = TimeZone(identifier: "Asia/Kathmandu")!
		let first = date("2026-06-01T00:00:00Z")
		let last = first.addingTimeInterval(30 * day)
		let position = first.addingTimeInterval(10 * day + 1234)

		let hourly = LocalStatsChartTicks.ticks(
			visible: 6 * hour, labelCount: 6, scrollPosition: position, dataRange: first...last, timeZone: kathmandu
		)
		#expect(hourly.count >= 6)
		#expect(hourly.allSatisfy { localComponents($0, in: kathmandu).minute == 0 })
		// Kathmandu is UTC+5:45, so its round hours fall at a quarter past in UTC.
		#expect(hourly.allSatisfy { localComponents($0, in: utc).minute == 15 })

		let halfDaily = LocalStatsChartTicks.ticks(
			visible: day, labelCount: 2, scrollPosition: position, dataRange: first...last, timeZone: kathmandu
		)
		#expect(halfDaily.count >= 2)
		for tick in halfDaily {
			let components = localComponents(tick, in: kathmandu)
			#expect((components.hour == 0 || components.hour == 12) && components.minute == 0, "\(tick)")
		}

		let daily = LocalStatsChartTicks.ticks(
			visible: 7 * day, labelCount: 6, scrollPosition: position, dataRange: first...last, timeZone: kathmandu
		)
		#expect(daily.count >= 6)
		for tick in daily {
			let components = localComponents(tick, in: kathmandu)
			#expect(components.hour == 0 && components.minute == 0, "\(tick)")
		}
	}

	@Test("Readings stamped in the future or far in the past stay off the chart")
	func plottableCutoffs() {
		let now = date("2026-10-20T12:00:00Z")
		func point(_ offset: TimeInterval) -> LocalStatsChartPoint {
			LocalStatsChartPoint(time: now.addingTimeInterval(offset), noiseFloor: -100)
		}
		let epoch = LocalStatsChartPoint(time: Date(timeIntervalSince1970: 0), noiseFloor: -100)
		let newestFirst = [point(400 * day), point(30 * 60), point(0), point(-364 * day), point(-366 * day), epoch]
		let plotted = LocalStatsChartPoint.plottable(newestFirst, now: now)
		#expect(plotted == [point(-364 * day), point(0), point(30 * 60)])
		#expect(LocalStatsChartPoint.plottable([], now: now).isEmpty)
	}

	@Test("A node whose clock runs more than an hour fast still gets a chart")
	func plottableClockRunningFast() {
		let now = date("2026-10-20T12:00:00Z")
		func point(_ offset: TimeInterval) -> LocalStatsChartPoint {
			LocalStatsChartPoint(time: now.addingTimeInterval(offset), noiseFloor: -100)
		}
		let newestFirst = [point(3 * hour), point(2 * hour), point(90 * 60)]
		#expect(LocalStatsChartPoint.plottable(newestFirst, now: now) == [point(90 * 60), point(2 * hour), point(3 * hour)])
		#expect(LocalStatsChartPoint.plottable([point(2 * hour)], now: now) == [point(2 * hour)])
		// Every reading past the 30 days: still drawn, anchored on the newest.
		let allFarAhead = [point(60 * day), point(59 * day)]
		#expect(LocalStatsChartPoint.plottable(allFarAhead, now: now) == [point(59 * day), point(60 * day)])
	}

	@Test("A clock that jumped ahead keeps both its fast readings and its older correct ones")
	func plottableClockJumpedAhead() {
		let now = date("2026-10-20T12:00:00Z")
		func point(_ offset: TimeInterval) -> LocalStatsChartPoint {
			LocalStatsChartPoint(time: now.addingTimeInterval(offset), noiseFloor: -100)
		}
		let newestFirst = [point(2 * hour), point(71 * 60), point(-2 * day)]
		#expect(LocalStatsChartPoint.plottable(newestFirst, now: now) == [point(-2 * day), point(71 * 60), point(2 * hour)])
		// A bad timestamp years out doesn't take the fast readings with it.
		let withOutlier = [point(5 * 365 * day), point(2 * hour), point(-day)]
		#expect(LocalStatsChartPoint.plottable(withOutlier, now: now) == [point(-day), point(2 * hour)])
	}

	@Test("One reading per timestamp, the first the fetch returns")
	func plottableDropsDuplicateTimestamps() {
		let now = date("2026-10-20T12:00:00Z")
		let newest = LocalStatsChartPoint(time: now, noiseFloor: -100)
		let duplicate = LocalStatsChartPoint(time: now, noiseFloor: -90)
		let older = LocalStatsChartPoint(time: now.addingTimeInterval(-hour), noiseFloor: -95)
		let olderDuplicate = LocalStatsChartPoint(time: now.addingTimeInterval(-hour), noiseFloor: -80)
		let plotted = LocalStatsChartPoint.plottable([newest, duplicate, older, olderDuplicate], now: now)
		#expect(plotted == [older, newest])
		#expect(Set(plotted.map(\.id)).count == plotted.count)
	}

	@Test("The year of history is measured from the newest reading that is drawn")
	func historyMeasuredFromNewestDrawnReading() {
		let now = date("2026-10-20T12:00:00Z")
		let future = LocalStatsChartPoint(time: now.addingTimeInterval(400 * day), noiseFloor: -100)
		let newest = LocalStatsChartPoint(time: now.addingTimeInterval(-30 * day), noiseFloor: -100)
		let old = LocalStatsChartPoint(time: now.addingTimeInterval(-390 * day), noiseFloor: -100)
		let older = LocalStatsChartPoint(time: now.addingTimeInterval(-400 * day), noiseFloor: -100)
		#expect(LocalStatsChartPoint.plottable([future, newest, old, older], now: now) == [old, newest])
	}
}
