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
