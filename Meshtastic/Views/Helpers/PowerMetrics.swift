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
	/// The node's power channel labels, so the tiles name channels as the log does.
	var labels: [String] = []

	var body: some View {

		LazyVGrid(columns: gridItemLayout) {
			ForEach(0..<TelemetryEntity.powerChannelCount, id: \.self) { index in
				let name = PowerChannelLabel.name(index, in: labels)
				if let voltage = metric.powerVoltage(channel: index) {
					PowerMetricCompactWidget(
						type: .voltage,
						value: voltage,
						title: String(localized: "\(name) Voltage", comment: "Power tile title. %@ is the channel's label, such as Solar or Channel 1.")
					)
				}
				if let current = metric.powerCurrent(channel: index) {
					PowerMetricCompactWidget(
						type: .current,
						value: current,
						title: String(localized: "\(name) Current", comment: "Power tile title. %@ is the channel's label, such as Solar or Channel 1.")
					)
				}
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
				.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 120)
				.padding()
				.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
		}
}

#Preview {
	let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	Form {
		LazyVGrid(columns: gridItemLayout) {
			PowerMetricCompactWidget(type: .voltage, value: 3.72, title: "Channel 1 Voltage")
			PowerMetricCompactWidget(type: .current, value: 125.3, title: "Channel 1 Current")
			PowerMetricCompactWidget(type: .voltage, value: 5.01, title: "Channel 2 Voltage")
			PowerMetricCompactWidget(type: .current, value: 42.7, title: "Channel 2 Current")
		}
	}
}
