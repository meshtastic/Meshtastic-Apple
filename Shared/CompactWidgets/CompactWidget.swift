//
//  CompactWidget.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//

import SwiftUI

extension View {
	/// The square tile every compact widget sits in. The tile takes its column's width and is as
	/// tall as it is wide. Its content is laid out at one size and scaled to the tile, so it fills
	/// the tile the same way on node details and in the widget, at any size.
	func compactWidgetTile() -> some View {
		modifier(CompactWidgetTile())
	}
}

private struct CompactWidgetTile: ViewModifier {

	/// The side the content is laid out at. A node details tile on a phone is about 165 points,
	/// so its readings come out about a third larger than this.
	private static let layoutSide: CGFloat = 125

	func body(content: Content) -> some View {
		GeometryReader { geometry in
			let side = min(geometry.size.width, geometry.size.height)
			let scale = max(0.1, side / Self.layoutSide)
			content
				.lineLimit(1)
				.minimumScaleFactor(0.4)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
				.padding(12)
				.frame(width: Self.layoutSide, height: Self.layoutSide)
				.background(Color("Colors/MeshtasticTile"), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
				.scaleEffect(scale)
				.frame(width: geometry.size.width, height: geometry.size.height)
		}
		.aspectRatio(1, contentMode: .fit)
	}
}

// Previews every compact widget in one place.

#Preview {

	let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	Form {
		LazyVGrid(columns: gridItemLayout) {
			HumidityCompactWidget(humidity: 27, dewPoint: "32°")
			HumidityCompactWidget(humidity: 27, dewPoint: nil)
			WeatherConditionsCompactWidget(temperature: "24°F", symbolName: "sun.rain.fill", description: "Raining")
			PressureCompactWidget(pressure: "1005", unit: "hPa", low: true)
			PressureCompactWidget(pressure: "1005", unit: "hPa", low: false)
			WindCompactWidget(speed: "12 mph", gust: "15 mph", direction: "SW")
			WindCompactWidget(speed: "12 mph", gust: nil, direction: "SW")
			WindCompactWidget(speed: "12 mph", gust: "15 mph", direction: nil)
			WindCompactWidget(speed: "12 mph", gust: nil, direction: nil)
			RadiationCompactWidget(radiation: "15", unit: "µR/hr")
			DistanceCompactWidget(distance: "123", unit: "mm")
			WeightCompactWidget(weight: "123", unit: "kg")
			SoilTemperatureCompactWidget(temperature: "23", unit: "°C")
			SoilMoistureCompactWidget(moisture: "23", unit: "%")

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
