//
//  PowerMetricCompactWidget.swift
//  Meshtastic
//
//  Created by Matthew Davies on 1/24/25.
//

import SwiftUI

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
				.compactWidgetTile()
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
