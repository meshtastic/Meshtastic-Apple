//
//  TraceRouteLogModelTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import Foundation
import Testing
@testable import Meshtastic

@Suite("Trace route time windows")
struct TraceRouteTimeWindowTests {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	@Test("With a log, 1h and All are offered, the others once the log reaches back that far")
	func availableWindows() {
		#expect(TraceRouteTimeWindow.available(oldest: nil, now: now) == [.all])
		#expect(TraceRouteTimeWindow.available(oldest: now.addingTimeInterval(-600), now: now) == [.hour, .all])
		#expect(TraceRouteTimeWindow.available(oldest: now.addingTimeInterval(-86_400), now: now) == [.hour, .day, .all])
		#expect(TraceRouteTimeWindow.available(oldest: now.addingTimeInterval(-3 * 86_400), now: now) == [.hour, .day, .all])
		#expect(TraceRouteTimeWindow.available(oldest: now.addingTimeInterval(-20 * 86_400), now: now) == [.hour, .day, .week, .twoWeeks, .all])
		#expect(TraceRouteTimeWindow.available(oldest: now.addingTimeInterval(-90 * 86_400), now: now) == TraceRouteTimeWindow.allCases)
	}

	@Test("A window keeps entries inside it and drops older ones")
	func filtering() {
		#expect(TraceRouteTimeWindow.hour.contains(now.addingTimeInterval(-1_800), now: now))
		#expect(!TraceRouteTimeWindow.hour.contains(now.addingTimeInterval(-7_200), now: now))
		#expect(TraceRouteTimeWindow.week.contains(now.addingTimeInterval(-6 * 86_400), now: now))
		#expect(!TraceRouteTimeWindow.week.contains(now.addingTimeInterval(-8 * 86_400), now: now))
		#expect(TraceRouteTimeWindow.all.contains(.distantPast, now: now))
	}

	@Test("An entry without a date only shows under All")
	func undatedEntries() {
		#expect(TraceRouteTimeWindow.all.contains(nil, now: now))
		#expect(!TraceRouteTimeWindow.month.contains(nil, now: now))
	}

	@Test("Every window has a label")
	func labels() {
		for window in TraceRouteTimeWindow.allCases {
			#expect(!window.label.isEmpty)
		}
	}
}

@Suite("Trace route card summary")
struct TraceRouteCardModelTests {

	private func card(_ state: TraceRouteState, towards: Int = 0, back: Int? = 0, roundTrip: TimeInterval? = nil) -> TraceRouteCardModel {
		TraceRouteCardModel(title: nil, date: .now, state: state, hopsTowards: towards, hopsBack: back, roundTrip: roundTrip)
	}

	@Test("States without a route show the state")
	func stateSummaries() {
		#expect(card(.pending).summary == TraceRouteState.pending.label)
		#expect(card(.noResponse).summary == TraceRouteState.noResponse.label)
		#expect(card(.rateLimited).summary == TraceRouteState.rateLimited.label)
		#expect(!card(.pending).hasRoute)
	}

	@Test("Zero hops both ways reads as direct")
	func direct() {
		#expect(card(.complete).summary == String(localized: "Direct"))
		#expect(card(.observed, back: nil).summary == String(localized: "Direct"))
	}

	@Test("Same hops both ways shows one count")
	func sameHops() {
		#expect(card(.complete, towards: 3, back: 3).summary == TraceRouteCardModel.hops(3))
		#expect(card(.complete, towards: 2, back: nil).summary == TraceRouteCardModel.hops(2))
	}

	@Test("Different hops show both counts")
	func differentHops() {
		let summary = card(.complete, towards: 3, back: 4).summary
		#expect(summary.contains(TraceRouteCardModel.hops(3)))
		#expect(summary.contains(TraceRouteCardModel.hops(4)))
	}

	@Test("Round trip is formatted in seconds with one decimal")
	func roundTripFormatting() {
		#expect(TraceRouteCardModel.formattedRoundTrip(7.34).contains("7.3"))
		#expect(TraceRouteCardModel.formattedRoundTrip(5).contains("5.0"))
		#expect(!TraceRouteCardModel.formattedRoundTrip(5, trimsWholeSeconds: true).contains("5.0"))
		#expect(TraceRouteCardModel.formattedRoundTrip(0.25, trimsWholeSeconds: true).contains("0.25"))
	}
}

@Suite("Trace route chart data")
struct TraceRouteChartTests {
	private let base = Date(timeIntervalSince1970: 1_800_000_000)

	private func entry(_ id: Int64, _ offset: TimeInterval, _ state: TraceRouteState, towards: Int = 1, back: Int? = 1, roundTrip: TimeInterval? = nil) -> (id: Int64, card: TraceRouteCardModel) {
		(id: id, card: TraceRouteCardModel(title: nil, date: base.addingTimeInterval(offset), state: state, hopsTowards: towards, hopsBack: back, roundTrip: roundTrip))
	}

	@Test("Only routes that came back are plotted, oldest first")
	func points() {
		let points = TraceRouteChartPoint.points(from: [
			entry(3, 300, .complete, towards: 2, back: 3, roundTrip: 9),
			entry(2, 200, .noResponse),
			entry(1, 100, .observed, towards: 1, back: nil)
		])
		#expect(points.map(\.id) == [1, 3])
		#expect(points[0].backHops == nil)
		#expect(points[0].roundTrip == nil)
		#expect(points[1].forwardHops == 2)
		#expect(points[1].backHops == 3)
		#expect(points[1].roundTrip == 9)
	}

	@Test("Selection picks the point nearest in time")
	func nearest() {
		let points = TraceRouteChartPoint.points(from: [entry(1, 0, .complete), entry(2, 100, .complete), entry(3, 1_000, .complete)])
		#expect(TraceRouteChartPoint.nearest(to: base.addingTimeInterval(40), in: points)?.id == 1)
		#expect(TraceRouteChartPoint.nearest(to: base.addingTimeInterval(400), in: points)?.id == 2)
		#expect(TraceRouteChartPoint.nearest(to: base.addingTimeInterval(5_000), in: points)?.id == 3)
		#expect(TraceRouteChartPoint.nearest(to: base, in: []) == nil)
	}

	@Test("Round trips are scaled onto the hop axis and back")
	func scale() {
		let points = TraceRouteChartPoint.points(from: [
			entry(1, 0, .complete, towards: 2, back: 4, roundTrip: 10),
			entry(2, 10, .complete, towards: 1, back: 1, roundTrip: 5)
		])
		let scale = TraceRouteChartScale(points: points)
		#expect(scale.maxHops == 4)
		#expect(scale.maxRoundTrip == 12)
		#expect(scale.plotted(roundTrip: 12) == 4)
		#expect(abs(scale.roundTrip(atPlotted: scale.plotted(roundTrip: 5)) - 5) < 0.0001)
		#expect(scale.hopTicks == [0, 1, 2, 3, 4])
		#expect(scale.roundTripTicks.first == 0)
		#expect(scale.roundTripTicks.last == 4)
	}

	@Test("The round trip axis uses round steps")
	func roundTripSteps() {
		#expect(TraceRouteChartScale.roundTripStep(for: 2.2) == 1)
		#expect(TraceRouteChartScale.roundTripStep(for: 14.9) == 5)
		#expect(TraceRouteChartScale.roundTripStep(for: 600) == 300)
	}

	@Test("Direct routes without round trips still get a usable scale")
	func emptyScale() {
		let scale = TraceRouteChartScale(points: TraceRouteChartPoint.points(from: [entry(1, 0, .complete, towards: 0, back: 0)]))
		#expect(scale.maxHops == 1)
		#expect(scale.maxRoundTrip == 1)
		#expect(!scale.hasRoundTrip)
		#expect(TraceRouteChartScale(points: TraceRouteChartPoint.points(from: [entry(1, 0, .complete, roundTrip: 3)])).hasRoundTrip)
	}

	@Test("The time axis shows the time of day for points within a day")
	func timeAxis() {
		let sameDay = TraceRouteChartPoint.points(from: [entry(1, 0, .complete), entry(2, 20 * 3_600, .complete)])
		#expect(TraceRouteChartPoint.showsTimeOfDay(sameDay))
		let twoDays = TraceRouteChartPoint.points(from: [entry(1, 0, .complete), entry(2, 30 * 3_600, .complete)])
		#expect(!TraceRouteChartPoint.showsTimeOfDay(twoDays))
		#expect(TraceRouteChartPoint.showsTimeOfDay([]))
	}
}
