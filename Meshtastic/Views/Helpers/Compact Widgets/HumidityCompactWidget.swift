//
//  HumidityCompactWidget.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//
import SwiftUI

struct HumidityCompactWidget: View {
	let humidity: Int
	let dewPoint: String?
	var body: some View {
		VStack(alignment: .leading) {
			HStack(spacing: 5.0) {
				Image(systemName: "humidity")
					.foregroundColor(.accentColor)
					.font(.callout)
				Text("Humidity")
					.textCase(.uppercase)
					.font(.caption)
			}
			Text("\(humidity)%")
				.font(.largeTitle)
				.padding(.bottom, 5)
			if let dewPoint {
				Text("The dew point is \(dewPoint) right now.")
					.lineLimit(3)
					.allowsTightening(true)
					.font(.caption2)
			}
		}
		.compactWidgetTile()
	}
}

#Preview {
	let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	Form {
		LazyVGrid(columns: gridItemLayout) {
			HumidityCompactWidget(humidity: 27, dewPoint: "32°")
			HumidityCompactWidget(humidity: 27, dewPoint: nil)
		}
	}
}
