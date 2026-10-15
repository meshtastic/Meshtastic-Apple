//
//  TraceRouteLogModel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import Foundation

/// How far back the trace route log looks.
enum TraceRouteTimeWindow: String, CaseIterable, Identifiable {
	case hour
	case day
	case week
	case twoWeeks
	case month
	case all

	var id: String { rawValue }

	/// Length of the window; nil for `all`.
	var interval: TimeInterval? {
		switch self {
		case .hour: 3_600
		case .day: 86_400
		case .week: 7 * 86_400
		case .twoWeeks: 14 * 86_400
		case .month: 30 * 86_400
		case .all: nil
		}
	}

	/// Short label such as "1h", "24h", "1w", "2w" or "1mo", formatted for the current locale.
	var label: String {
		let formatter = DateComponentsFormatter()
		formatter.unitsStyle = .abbreviated
		formatter.maximumUnitCount = 1
		var components = DateComponents()
		switch self {
		case .hour:
			formatter.allowedUnits = [.hour]
			components.hour = 1
		case .day:
			formatter.allowedUnits = [.hour]
			components.hour = 24
		case .week:
			formatter.allowedUnits = [.weekOfMonth]
			components.weekOfMonth = 1
		case .twoWeeks:
			formatter.allowedUnits = [.weekOfMonth]
			components.weekOfMonth = 2
		case .month:
			formatter.allowedUnits = [.month]
			components.month = 1
		case .all:
			return String(localized: "All")
		}
		return formatter.string(from: components) ?? rawValue
	}

	/// The windows to offer: `all` always; once there is a log, `hour` too, and each other window
	/// once the log reaches back that far. The same rule as the Android app's metrics time frames.
	static func available(oldest: Date?, now: Date = .now) -> [TraceRouteTimeWindow] {
		guard let oldest else { return [.all] }
		let age = now.timeIntervalSince(oldest)
		return allCases.filter { window in
			guard let interval = window.interval, window != .hour else { return true }
			return age >= interval
		}
	}

	/// Whether a log entry from `date` falls inside the window.
	func contains(_ date: Date?, now: Date = .now) -> Bool {
		guard let interval else { return true }
		guard let date else { return false }
		return now.timeIntervalSince(date) <= interval
	}
}

/// What a trace route log card shows, taken from plain values so it can be tested and previewed
/// without SwiftData.
struct TraceRouteCardModel: Equatable {
	/// "Origin → Target" in the app-wide log; nil in a node's own log.
	var title: String?
	var date: Date?
	var state: TraceRouteState
	var hopsTowards: Int
	/// Nil when the response didn't carry a return path.
	var hopsBack: Int?
	var roundTrip: TimeInterval?

	/// Whether the route came back, so hop counts mean something.
	var hasRoute: Bool { state == .complete || state == .observed }

	/// One line: "Direct", "3 Hops", "3 Hops out · 4 Hops back", or the state.
	var summary: String {
		if let label = state.label { return label }
		if hopsTowards == 0 && (hopsBack ?? 0) == 0 {
			return String(localized: "Direct")
		}
		let towards = Self.hops(hopsTowards)
		guard let hopsBack, hopsBack != hopsTowards else { return towards }
		return String(
			localized: "\(towards) out · \(Self.hops(hopsBack)) back",
			comment: "Trace route card when the forward and return paths differ, e.g. \"3 Hops out · 4 Hops back\""
		)
	}

	static func hops(_ count: Int) -> String {
		String(localized: "\(Int32(count)) Hops")
	}

	/// Round trip as "7.3 sec", formatted for the current locale. Axis labels set
	/// `trimsWholeSeconds`, which shows "5 sec" and "0.25 sec" instead of "5.0 sec" and "0.3 sec".
	static func formattedRoundTrip(_ value: TimeInterval, trimsWholeSeconds: Bool = false) -> String {
		// Whole milliseconds, so axis values computed by scaling don't read as 2.9999 s.
		let seconds = (value * 1000).rounded() / 1000
		var fraction = 1
		if trimsWholeSeconds {
			if seconds.rounded() == seconds {
				fraction = 0
			} else if (seconds * 10).rounded() != seconds * 10 {
				fraction = 2
			}
		}
		return Duration.milliseconds(Int64((seconds * 1000).rounded()))
			.formatted(.units(allowed: [.seconds], width: .abbreviated, fractionalPart: .show(length: fraction)))
	}
}

extension TraceRouteCardModel {
	init(route: TraceRouteEntity, title: String? = nil, now: Date = .now) {
		self.init(
			title: title,
			date: route.time ?? route.sentAt,
			state: route.state(now: now),
			hopsTowards: Int(route.hopsTowards),
			hopsBack: route.hopsBack >= 0 ? Int(route.hopsBack) : nil,
			roundTrip: route.roundTrip
		)
	}
}

/// One trace route on the log chart.
struct TraceRouteChartPoint: Equatable, Identifiable {
	/// The trace route's request id.
	let id: Int64
	let date: Date
	let forwardHops: Int
	/// Nil when the response didn't carry a return path.
	let backHops: Int?
	let roundTrip: TimeInterval?

	/// Points for the routes that came back, oldest first. Routes still waiting, without a
	/// response or rate limited have no hops to plot.
	static func points(from cards: [(id: Int64, card: TraceRouteCardModel)]) -> [TraceRouteChartPoint] {
		cards.compactMap { entry in
			guard entry.card.hasRoute, let date = entry.card.date else { return nil }
			return TraceRouteChartPoint(
				id: entry.id,
				date: date,
				forwardHops: entry.card.hopsTowards,
				backHops: entry.card.hopsBack,
				roundTrip: entry.card.roundTrip
			)
		}
		.sorted { $0.date < $1.date }
	}

	/// Whether the points fall within a day, so the time axis shows the time of day rather than
	/// the date. Expects `points` oldest first, as `points(from:)` returns them.
	static func showsTimeOfDay(_ points: [TraceRouteChartPoint]) -> Bool {
		guard let first = points.first?.date, let last = points.last?.date else { return true }
		return last.timeIntervalSince(first) < 86_400
	}

	/// The point closest in time to `date`, for chart selection.
	static func nearest(to date: Date, in points: [TraceRouteChartPoint]) -> TraceRouteChartPoint? {
		points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
	}
}

/// Puts round trip seconds on the same plot as hop counts. Swift Charts has one y scale, so round
/// trips are scaled into the hop range and the trailing axis labels convert back to seconds.
struct TraceRouteChartScale: Equatable {
	/// Top of the hop axis.
	let maxHops: Double
	/// Top of the round trip axis, in seconds.
	let maxRoundTrip: Double
	/// Whether any point has a round trip; without one the round trip axis is left off.
	let hasRoundTrip: Bool

	init(points: [TraceRouteChartPoint]) {
		let hops = points.flatMap { [$0.forwardHops, $0.backHops ?? 0] }.max() ?? 0
		maxHops = Double(max(hops, 1))
		let roundTrips = points.compactMap(\.roundTrip)
		hasRoundTrip = !roundTrips.isEmpty
		let longest = roundTrips.max() ?? 0
		maxRoundTrip = Self.roundTripStep(for: longest) * 4
	}

	/// A round step for the four round trip labels, with a little room above the longest one.
	static func roundTripStep(for longest: TimeInterval) -> TimeInterval {
		let steps: [TimeInterval] = [0.25, 0.5, 1, 2, 2.5, 3, 4, 5, 10, 15, 20, 30, 60, 120, 300]
		let wanted = longest * 1.1 / 4
		return steps.first { $0 >= wanted } ?? (wanted / 60).rounded(.up) * 60
	}

	/// Where a round trip sits on the hop axis.
	func plotted(roundTrip: TimeInterval) -> Double {
		roundTrip / maxRoundTrip * maxHops
	}

	/// The round trip a position on the hop axis stands for.
	func roundTrip(atPlotted value: Double) -> TimeInterval {
		value / maxHops * maxRoundTrip
	}

	/// Whole hop counts for the leading axis.
	var hopTicks: [Double] {
		let step = maxHops <= 6 ? 1.0 : (maxHops / 4).rounded(.up)
		return Array(stride(from: 0, through: maxHops, by: step))
	}

	/// Plot positions for four evenly spaced round trip labels on the trailing axis.
	var roundTripTicks: [Double] {
		(0...4).map { maxHops * Double($0) / 4 }
	}
}
