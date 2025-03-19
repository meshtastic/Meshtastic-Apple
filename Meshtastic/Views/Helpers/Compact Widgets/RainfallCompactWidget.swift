//
//  RainfallCompactWidgets.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/15/25.
//

import SwiftUI

struct RainfallCompactWidget: View {
	enum RainfallTimeSpan: String {
		case rainfall1H = "Rainfall 1H"
		case rainfall24H = "Rainfall 24H"
	}

	let timespan: RainfallTimeSpan
	let rainfall: String
	let unit: String

	private var icon: Image {
		if timespan == .rainfall1H {
			return Image(systemName: "cloud.rain.fill")
		}
		return Image(systemName: "cloud.heavyrain.fill")
	}

	var body: some View {
		VStack(alignment: .leading) {
			HStack(alignment: .firstTextBaseline) {
				icon.imageScale(.small)
					.foregroundColor(.accentColor)
				Text(timespan.rawValue)
					.textCase(.uppercase)
					.font(.callout)
			}
			HStack {
				Text("\(rainfall)")
					.font(rainfall.length < 4 ? .system(size: 50) : .system(size: 40) )
				Text(unit)
					.font(.system(size: 14))
			}
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
			let rain: Float = 10.1
			let locale = NSLocale.current as NSLocale
			let usesMetricSystem = locale.usesMetricSystem // Returns true for metric (mm), false for imperial (inches)
			let unit = usesMetricSystem ? UnitLength.millimeters : UnitLength.inches
			let unitLabel = usesMetricSystem ? "mm" : "in"
			let measurement = Measurement(value: Double(rain), unit: UnitLength.millimeters)
			let decimals = usesMetricSystem ? 0 : 1
			let formattedRain = measurement.converted(to: unit).value.formatted(.number.precision(.fractionLength(decimals)))

			RainfallCompactWidget(timespan: .rainfall1H, rainfall: formattedRain, unit: unitLabel)
			RainfallCompactWidget(timespan: .rainfall24H, rainfall: formattedRain, unit: unitLabel)
		}
	}
}
