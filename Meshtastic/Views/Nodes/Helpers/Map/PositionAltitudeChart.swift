//
//  PositionAltitudeChart.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/17/23.
//

import SwiftUI
import Charts
#if canImport(MapKit)
import MapKit
#endif


@available(iOS 17.0, macOS 14.0, *)
struct PositionAltitudeChart: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject var node: NodeInfoEntity
	
	@State private var lineWidth = 2.0
	@State private var interpolationMethod: ChartInterpolationMethod = .linear
	@State private var chartColor: Color = .accentColor
	@State private var showSymbols = true
	
	var body: some View {
		let nodePositions = Array(node.positions!) as! [PositionEntity]
		let data = nodePositions.map { PositionAltitude(time: $0.time ?? Date(), altitude: Measurement(value: Double($0.altitude), unit: .meters) ) }
		HStack {
			Chart(data, id: \.time) {
				LineMark(
					x: .value("Time", $0.time),
					y: .value("Altitude", PlottableMeasurement(measurement: $0.altitude))
				)
				.accessibilityLabel($0.time.formatted(date: .abbreviated, time: .shortened))
				.accessibilityValue("\($0.altitude) ft high")
				.lineStyle(StrokeStyle(lineWidth: lineWidth))
				.foregroundStyle(chartColor.gradient)
				.interpolationMethod(interpolationMethod.mode)
				.symbol(Circle().strokeBorder(lineWidth: lineWidth))
				.symbolSize(showSymbols ? 60 : 0)
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
		.padding()
		.background(Color(UIColor.secondarySystemBackground))
		.opacity(/*@START_MENU_TOKEN@*/0.8/*@END_MENU_TOKEN@*/)
	}
}

struct PositionAltitude {
	let time: Date
	var altitude: Measurement<UnitLength>
}

enum ChartInterpolationMethod: Identifiable, CaseIterable {
	case linear
	case monotone
	case catmullRom
	case cardinal
	case stepStart
	case stepCenter
	case stepEnd
	
	var id: String { mode.description }
	
	var mode: InterpolationMethod {
		switch self {
		case .linear:
			return .linear
		case .monotone:
			return .monotone
		case .stepStart:
			return .stepStart
		case .stepCenter:
			return .stepCenter
		case .stepEnd:
			return .stepEnd
		case .catmullRom:
			return .catmullRom
		case .cardinal:
			return .cardinal
		}
	}
}
