//
//  CompactWidget.swift
//  Meshtastic
//
//  Created by Jake Bordens on 3/14/25.
//

import SwiftUI

// This file was created for the purpose of previewing
// all of the Compact Widgets in one place.

// In the future, it could be used for a CompactWidget superclass, if desired.

#Preview {

	let gridItemLayout = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
	Form {
		LazyVGrid(columns: gridItemLayout) {
			HumidityCompactWidget(humidity: 27, dewPoint: "32°")
			HumidityCompactWidget(humidity: 27, dewPoint: nil)
			WeatherConditionsCompactWidget(temperature: "24°F", symbolName: "sun.rain.fill", description: "Raining")
			PressureCompactWidget(pressure: "1004.76", unit: "hPA", low: true)
			PressureCompactWidget(pressure: "1004.76", unit: "hPA", low: false)
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
