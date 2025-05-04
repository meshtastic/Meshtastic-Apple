//
//  PowerMetrics.swift
//  Meshtastic
//
//  Created by Matthew Davies on 1/24/25.
//

import Foundation
import SwiftUI

struct PowerMetrics: View {
	private let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

	let metric: TelemetryEntity

	var body: some View {

		LazyVGrid(columns: gridItemLayout) {

			if let powerCh1Voltage = metric.powerCh1Voltage {
				PowerMetricCompactWidget(
					type: .voltage,
					value: powerCh1Voltage,
					title: "Channel 1 Voltage"
				)
			}

			if let powerCh1Current = metric.powerCh1Current {
				PowerMetricCompactWidget(
					type: .current,
					value: powerCh1Current,
					title: "Channel 1 Current"
				)
			}

			if let powerCh2Voltage = metric.powerCh2Voltage {
				PowerMetricCompactWidget(
					type: .voltage,
					value: powerCh2Voltage,
					title: "Channel 2 Voltage"
				)
			}

			if let powerCh2Current = metric.powerCh2Current {
				PowerMetricCompactWidget(
					type: .current,
					value: powerCh2Current,
					title: "Channel 2 Current"
				)
			}

			if let powerCh3Voltage = metric.powerCh3Voltage {
				PowerMetricCompactWidget(
					type: .voltage,
					value: powerCh3Voltage,
					title: "Channel 3 Voltage"
				)
			}

			if let powerCh3Current = metric.powerCh3Current {
				PowerMetricCompactWidget(
					type: .current,
					value: powerCh3Current,
					title: "Channel 3 Current"
				)
			}
		}
	}
}

enum PowerMetricType: String {
	case current = "Current"
	case voltage = "Voltage"
}

struct PowerMetricCompactWidget: View {
		let type: PowerMetricType
		let value: Float
		let title: String
		var body: some View {
				VStack(alignment: .leading) {
						HStack(spacing: 5.0) {
							Image(systemName: type == .current ? "bolt.fill" : "powerplug.fill")
										.foregroundColor(.accentColor)
										.font(.callout)
								Text(title)
										.font(.caption)
						}
						Text("\(value, specifier: type == .current ? "%.1f" : "%.2f") \(type == .current ? "mA" : "V")")
								.font(type == .current ? .system(size: 35) : .system(size: 30))
				}
				.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 120, idealHeight: 130, maxHeight: 140)
				.padding()
				.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		}
}
