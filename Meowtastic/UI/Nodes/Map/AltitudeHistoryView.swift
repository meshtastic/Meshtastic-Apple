import Charts
import MapKit
import SwiftUI

struct PositionAltitude {
	let time: Date
	var altitude: Measurement<UnitLength>
}

struct AltitudeHistoryView: View {
	@ObservedObject
	var node: NodeInfoEntity

	var fiveYearsAgo: Date = {
		// swiftlint:disable:next force_unwrapping
		Calendar.current.date(byAdding: .year, value: -5, to: Date.now)!
	}()

	var data: [PositionAltitude] {
		guard let nodePositions = node.positions,
			let positions = Array(nodePositions) as? [PositionEntity]
		else {
			return []
		}

		let filteredPositions = positions.filter { position in
			guard let time = position.time else {
				return false
			}

			return time > fiveYearsAgo
		}

		return filteredPositions.map { position in
			PositionAltitude(
				time: position.time ?? Date(),
				altitude: Measurement(
					value: Double(position.altitude),
					unit: .meters
				)
			)
		}
	}

	@ViewBuilder
	var body: some View {
		GroupBox(
			label: Label("Altitude", systemImage: "mountain.2")
				.font(.body)
		) {
			Chart(data, id: \.time) {
				LineMark(
					x: .value("Time", $0.time),
					y: .value("Altitude", PlottableMeasurement(measurement: $0.altitude))
				)
				.interpolationMethod(.stepCenter)
				.lineStyle(
					StrokeStyle(lineWidth: 3)
				)
				.cornerRadius(8)
				.accessibilityLabel($0.time.formatted(date: .abbreviated, time: .shortened))
				.accessibilityValue("\($0.altitude)")
			}
			.chartYAxis {
				AxisMarks { value in
					if let measurement = value.as(PlottableMeasurement.self)?
						.measurement
						.converted(to: UnitLength.meters)
					{
						let measurementFormatted = measurement.formatted(
							.measurement(
								width: .narrow,
								numberFormatStyle: .number.precision(
									.fractionLength(0)
								)
							)
						)

						AxisGridLine()
						AxisValueLabel(measurementFormatted)
					}
				}
			}
			.chartXAxis(.visible)
		}
	}
}
