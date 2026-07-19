//
//  PressureCompactWidget.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//
import SwiftUI

struct PressureCompactWidget: View {
	let pressure: String
	let unit: String
	let low: Bool

	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeLarge: CGFloat = 35
	@ScaledMetric(relativeTo: .largeTitle) private var valueSizeSmall: CGFloat = 30
	var body: some View {
		VStack(alignment: .leading) {
			HStack(spacing: 5.0) {
				Image(systemName: "gauge")
					.foregroundColor(.accentColor)
					.font(.callout)
				Text("Pressure")
					.textCase(.uppercase)
					.font(.caption)
			}
			Text(pressure)
				.font(.system(size: pressure.length < 7 ? valueSizeLarge : valueSizeSmall))
				.lineLimit(1)
				.minimumScaleFactor(0.5)
			Text(low ? "LOW" : "HIGH")
				.padding(.bottom, 10)
			Text(unit)
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
			PressureCompactWidget(pressure: "1004.76", unit: "hPA", low: true)
			PressureCompactWidget(pressure: "1004.76", unit: "hPA", low: false)
		}
	}
}
