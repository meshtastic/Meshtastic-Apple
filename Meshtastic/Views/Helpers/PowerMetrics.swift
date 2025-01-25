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


			if(metric.powerCh1Voltage != nil) {
				PowerMetricCompactWidget(
					type: .voltage,
					value: metric.powerCh1Voltage,
					title: "Channel 1 Voltage"
				)
			}

			if(metric.powerCh1Current != nil) {
				PowerMetricCompactWidget(
					type: .current,
					value: metric.powerCh1Current,
					title: "Channel 1 Current"
				)
			}

			if(metric.powerCh2Voltage != nil) {
				PowerMetricCompactWidget(
					type: .voltage,
					value: metric.powerCh2Voltage,
					title: "Channel 2 Voltage"
				)
			}

			if(metric.powerCh2Current != nil) {
				PowerMetricCompactWidget(
					type: .current,
					value: metric.powerCh2Current,
					title: "Channel 2 Current"
				)
			}

			if(metric.powerCh3Voltage != nil) {
				PowerMetricCompactWidget(
					type: .voltage,
					value: metric.powerCh3Voltage,
					title: "Channel 3 Voltage"
				)
			}

			if(metric.powerCh3Current != nil) {
				PowerMetricCompactWidget(
					type: .current,
					value: metric.powerCh3Current,
					title: "Channel 3 Current"
				)
			}
		}
	}
}

enum PowerMetricType: String {
	case current = "current"
	case voltage = "voltage"
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
