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
					.fixedSize(horizontal: false, vertical: true)
					.font(.caption)
			}
			Text(temperature)
				.font(temperature.length < 4 ? .system(size: 72) : .system(size: 54) )
		}
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 120, idealHeight: 130, maxHeight: 140)
		.padding()
		.background(.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
