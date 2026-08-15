//
//  PositionAltitudeChart.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/17/23.
//

import SwiftUI
import Charts
import MapKit
@preconcurrency import SwiftData

struct PositionAltitude {
	let time: Date
	var altitude: Measurement<UnitLength>
}

struct PositionAltitudeChart: View {
	private let visiblePositionLimit = 1_000

	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Bindable var node: NodeInfoEntity
	@State private var lineWidth = 2.0
	@State private var data: [PositionAltitude] = []

	var body: some View {
		GroupBox(label: Label("Altitude", systemImage: "mountain.2")) {
			Chart(data, id: \.time) {
				LineMark(
					x: .value("Time", $0.time),
					y: .value("Altitude", PlottableMeasurement(measurement: $0.altitude))
				)
				.accessibilityLabel(String(localized: "Altitude at \($0.time.formatted(date: .abbreviated, time: .shortened))", comment: "VoiceOver label for an altitude point on the position altitude chart. %@ is the timestamp."))
				.accessibilityValue($0.altitude.converted(to: Locale.current.measurementSystem == .metric ? .meters : .feet).formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
				.lineStyle(StrokeStyle(lineWidth: lineWidth))
				.interpolationMethod(.linear)
				.symbol(Circle().strokeBorder(lineWidth: lineWidth))
				.symbolSize(60)
			}
			.chartYAxis {
				AxisMarks { value in
					AxisGridLine()
					AxisValueLabel("""
						\(value.as(PlottableMeasurement.self)!
							.measurement
							.converted(to: Locale.current.measurementSystem == .metric ? .meters : .feet),
								format: .measurement(
									width: .wide,
									numberFormatStyle: .number.precision(
										.fractionLength(0))
									)
								)
					""")
				}
			}
			.chartXAxis(.visible)
		}
			.background(Color(UIColor.secondarySystemBackground))
			.opacity(/*@START_MENU_TOKEN@*/0.8/*@END_MENU_TOKEN@*/)
			.onAppear {
				loadChartData()
			}
	}

	private func loadChartData() {
		let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date.distantPast
		data = node.positionsSortedByTime(context: context, ascending: false, limit: visiblePositionLimit)
			.reversed()
			.compactMap { position in
				guard let time = position.time, time > fiveYearsAgo else { return nil }
				return PositionAltitude(
					time: time,
					altitude: Measurement(value: Double(position.altitude), unit: .meters)
				)
			}
	}
}
