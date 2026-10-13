//
//  TraceRouteChart.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import Charts
import SwiftUI

/// Hop counts over time, forward and back on the leading axis and the round trip on the trailing
/// axis. Tapping the chart picks the nearest trace route.
struct TraceRouteChart: View {
	let points: [TraceRouteChartPoint]
	@Binding var selectedID: Int64?

	@State private var rawSelection: Date?

	private var scale: TraceRouteChartScale { TraceRouteChartScale(points: points) }
	private var selectedPoint: TraceRouteChartPoint? {
		guard let selectedID else { return nil }
		return points.first { $0.id == selectedID }
	}

	private var forwardName: String { String(localized: "Forward hops", comment: "Trace route: hop count towards the target") }
	private var backName: String { String(localized: "Return hops", comment: "Trace route: hop count on the way back") }
	private var roundTripName: String { String(localized: "Round trip", comment: "Trace route: time from sending the request to getting the response") }

	/// Times of day when the points fall within a day, dates otherwise.
	private var dateFormat: Date.FormatStyle {
		TraceRouteChartPoint.showsTimeOfDay(points) ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day()
	}

	var body: some View {
		let scale = scale
		Chart {
			ForEach(points) { point in
				LineMark(x: .value("Time", point.date), y: .value("Hops", point.forwardHops), series: .value("Series", forwardName))
					.foregroundStyle(by: .value("Series", forwardName))
					.lineStyle(StrokeStyle(lineWidth: 2))
					.symbol(.circle)
					.accessibilityLabel(forwardName)
					.accessibilityValue(TraceRouteCardModel.hops(point.forwardHops))
				if let backHops = point.backHops {
					LineMark(x: .value("Time", point.date), y: .value("Hops", backHops), series: .value("Series", backName))
						.foregroundStyle(by: .value("Series", backName))
						.lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
						.symbol(.square)
						.accessibilityLabel(backName)
						.accessibilityValue(TraceRouteCardModel.hops(backHops))
				}
				if let roundTrip = point.roundTrip {
					LineMark(x: .value("Time", point.date), y: .value("Hops", scale.plotted(roundTrip: roundTrip)), series: .value("Series", roundTripName))
						.foregroundStyle(by: .value("Series", roundTripName))
						.lineStyle(StrokeStyle(lineWidth: 1.5))
						.symbol(.triangle)
						.accessibilityLabel(roundTripName)
						.accessibilityValue(TraceRouteCardModel.formattedRoundTrip(roundTrip))
				}
			}
			if let selectedPoint {
				RuleMark(x: .value("Time", selectedPoint.date))
					.foregroundStyle(Color.secondary.opacity(0.5))
					.accessibilityHidden(true)
			}
		}
		.chartForegroundStyleScale([
			forwardName: TraceRouteColors.forward,
			backName: TraceRouteColors.back,
			roundTripName: TraceRouteColors.roundTrip
		])
		.chartYScale(domain: 0...scale.maxHops)
		.chartYAxis {
			AxisMarks(position: .leading, values: scale.hopTicks) { value in
				AxisGridLine()
				AxisValueLabel {
					if let hops = value.as(Double.self) {
						Text(Int(hops), format: .number)
					}
				}
			}
			if scale.hasRoundTrip {
				AxisMarks(position: .trailing, values: scale.roundTripTicks) { value in
					AxisValueLabel {
						if let plotted = value.as(Double.self) {
							Text(TraceRouteCardModel.formattedRoundTrip(scale.roundTrip(atPlotted: plotted), trimsWholeSeconds: true))
								.foregroundStyle(TraceRouteColors.roundTrip)
						}
					}
				}
			}
		}
		.chartXAxis {
			AxisMarks(values: .automatic(desiredCount: 3)) { _ in
				AxisGridLine()
				AxisValueLabel(format: dateFormat, collisionResolution: .greedy(minimumSpacing: 8))
			}
		}
		.chartLegend(position: .bottom, alignment: .leading)
		.chartXSelection(value: $rawSelection)
		.onChange(of: rawSelection) { _, date in
			guard let date, let point = TraceRouteChartPoint.nearest(to: date, in: points) else { return }
			selectedID = point.id
		}
		.frame(height: 200)
	}
}
