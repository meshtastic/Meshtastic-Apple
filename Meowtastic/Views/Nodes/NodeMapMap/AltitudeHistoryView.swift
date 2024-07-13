import SwiftUI
import Charts
import MapKit

struct PositionAltitude {
	let time: Date
	var altitude: Measurement<UnitLength>
}

struct AltitudeHistoryView: View {
	@ObservedObject
	var node: NodeInfoEntity

	@Environment(\.dismiss)
	private var dismiss
	@State
	private var lineWidth = 2.0

	var data: [PositionAltitude] {
		let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date())
		guard let nodePositions = node.positions,
			let positions = Array(nodePositions) as? [PositionEntity]
		else {
			return []
		}

		let filteredPositions = positions.filter { position in
			position.time != nil && (position.time ?? fiveYearsAgo!) > fiveYearsAgo!
		}

		return filteredPositions.map { position in
			PositionAltitude(
				time: position.time ?? Date(),
				altitude: Measurement(value: Double(position.altitude), unit: .meters)
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
					let measurement = value.as(PlottableMeasurement.self)!
						.measurement
						.converted(to: UnitLength.meters)
					let measurementFormatted = measurement.formatted(
						.measurement(
							width: .wide,
							numberFormatStyle: .number.precision(
								.fractionLength(0)
							)
						)
					)

					AxisGridLine()
					AxisValueLabel(measurementFormatted)
				}
			}
			.chartXAxis(.visible)
		}
	}
}
