//
//  SoilCompactWidgets.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//

import SwiftUI

struct SoilTemperatureCompactWidget: View {
	let temperature: String
	let unit: String

	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeLarge: CGFloat = 50
	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeSmall: CGFloat = 40

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Image("soil.temperature")
					.imageScale(.small)
					.foregroundColor(.accentColor)
				Text("Soil Temp")
					.textCase(.uppercase)
					.font(.callout)
			}
			HStack {
				Text("\(temperature)")
					.font(.system(size: temperature.length < 4 ? valueSizeLarge : valueSizeSmall))
					.lineLimit(1)
					.minimumScaleFactor(0.5)
				Text(unit)
					.font(.footnote)
			}
		}
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 120, idealHeight: 130, maxHeight: 140)
		.padding()
		.background(Color("Colors/MeshtasticTile"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

struct SoilMoistureCompactWidget: View {
	let moisture: String
	let unit: String

	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeLarge: CGFloat = 50
	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeSmall: CGFloat = 40

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				Image("soil.moisture")
					.imageScale(.small)
					.foregroundColor(.accentColor)
				Text("Soil Moisture")
					.textCase(.uppercase)
					.font(.callout)
			}
			HStack {
				Text("\(moisture)")
					.font(.system(size: moisture.length < 4 ? valueSizeLarge : valueSizeSmall))
					.lineLimit(1)
					.minimumScaleFactor(0.5)
				Text(unit)
					.font(.footnote)
			}
		}
		.frame(minWidth: 100, idealWidth: 125, maxWidth: 150, minHeight: 120, idealHeight: 130, maxHeight: 140)
		.padding()
		.background(Color("Colors/MeshtasticTile"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
	}
}

#Preview {
	let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	Form {
		LazyVGrid(columns: gridItemLayout) {
			SoilTemperatureCompactWidget(temperature: "23", unit: "°C")
			SoilMoistureCompactWidget(moisture: "23", unit: "%")
		}
	}
}
