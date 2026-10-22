//
//  WeatherConditionsCompactWidget.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//
import SwiftUI

struct WeatherConditionsCompactWidget: View {
	let temperature: String
	let symbolName: String
	let description: String
	var body: some View {
		VStack(alignment: .leading) {
			HStack(spacing: 5.0) {
				Image(systemName: symbolName)
					.foregroundColor(.accentColor)
					.font(.callout)
				Text(description)
					.lineLimit(2)
					.allowsTightening(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
					.font(.caption)
			}
			Text(temperature)
				.font(temperature.length < 4 ? .system(size: 72) : .system(size: 54) )
		}
		.compactWidgetTile()
	}
}

#Preview {
	let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	Form {
		LazyVGrid(columns: gridItemLayout) {
			WeatherConditionsCompactWidget(temperature: "24°F", symbolName: "sun.rain.fill", description: "Raining")
		}
	}
}
