//
//  PositionAltitudeChart.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/17/23.
//

import SwiftUI
import Charts
import MapKit

struct PositionAltitude {
	let time: Date
	var altitude: Measurement<UnitLength>
}

@available(iOS 16.0, *)
struct PositionAltitudeChart: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject var node: NodeInfoEntity
	@State private var lineWidth = 2.0

	var data: [PositionAltitude] {
		let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date())
		guard let nodePositions = node.positions,
			let positions = Array(nodePositions) as? [PositionEntity]
		else {
			return []
		}

		let filteredPositions = positions.filter({$0.time != nil && ($0.time ?? fiveYearsAgo!) > fiveYearsAgo!})
		return filteredPositions.map {
			PositionAltitude(
				time: $0.time ?? Date(),
				altitude: Measurement(value: Double($0.altitude), unit: .meters)
			)
		}
	}

	var body: some View {
		GroupBox(label: Label("Altitude", systemImage: "mountain.2")) {
			Chart(data, id: \.time) {
				LineMark(
					x: .value("Time", $0.time),
					y: .value("Altitude", PlottableMeasurement(measurement: $0.altitude))
				)
				.accessibilityLabel($0.time.formatted(date: .abbreviated, time: .shortened))
				.accessibilityValue("\($0.altitude)")
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
							.converted(to: .meters),
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
	}
}
