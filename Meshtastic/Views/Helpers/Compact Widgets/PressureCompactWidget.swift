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
				.font(pressure.length < 7 ? .system(size: 35) : .system(size: 30) )
			Text(low ? "LOW" : "HIGH")
				.padding(.bottom, 10)
			Text(unit)
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
			PressureCompactWidget(pressure: "1004.76", unit: "hPA", low: true)
			PressureCompactWidget(pressure: "1004.76", unit: "hPA", low: false)
		}
	}
}
