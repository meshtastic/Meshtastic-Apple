//
//  EnvironmentDefaultSeries.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/11/24.
//

import Charts
import Foundation
import SwiftUI

// This is the default configuration used by the EnvironmentMetricsLog view for the chart
extension MetricsSeriesList {
	static var environmentDefaultChartSeries: MetricsSeriesList {
		MetricsSeriesList([
			// Temperature Series Configuration
			MetricsChartSeries(
				id: "temperature",
				keyPath: \.temperature,
				name: "Temperature",
				abbreviatedName: "Temp",
				minumumYAxisSpan: 50.0,
				conversion: { t in t.map { Float($0.localeTemperature()) } },
				foregroundStyle: { chartRange in
					let locale = NSLocale.current as NSLocale
					let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
					let format: UnitTemperature = localeUnit as? String ?? "Celsius" == "Fahrenheit" ? .fahrenheit : .celsius
					let lowerBound = chartRange.map { Double($0.lowerBound) } ?? 0.0
					let upperBound = chartRange.map { Double($0.upperBound) } ?? 100.0
					let stops: [Gradient.Stop] = generateStops(minTemp: lowerBound, maxTemp: upperBound, tempUnit: format, opacity: 1.0)
					return LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
				},
				chartBody: { series, chartRange, time, temperature in
					if let temperature {
						AreaMark(
							x: .value("Time", time),
							yStart: .value(series.abbreviatedName, chartRange?.lowerBound.doubleValue ?? 0.0),
							yEnd: .value(
								series.abbreviatedName, temperature.localeTemperature())
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.alignsMarkStylesWithPlotArea()
						.accessibilityHidden(true)
						.opacity(0.6)
						LineMark(
							x: .value("Time", time),
							y: .value(
								series.abbreviatedName, temperature.localeTemperature())
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Relative Humidity Series Configuration
			MetricsChartSeries(
				id: "relativeHumidity",
				keyPath: \.relativeHumidity,
				name: "Relative Humidity",
				abbreviatedName: "Hum",
				initialYAxisRange: 0.0...100.0,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.purple.darker(componentDelta: 0.2)), .purple],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, humidity in
					if let humidity {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, humidity)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Barometric Pressure Series Configuration
			MetricsChartSeries(
				id: "barometricPressure",
				keyPath: \.barometricPressure,
				name: "Barometric Pressure",
				abbreviatedName: "Bar",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.green.darker(componentDelta: 0.3)), .green],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, pressure in
					if let pressure {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, pressure)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Indoor Air Quality Series Configuration
			MetricsChartSeries(
				id: "iaq",
				keyPath: \.iaq,
				name: "Indoor Air Quality",
				abbreviatedName: "IAQ",
				visible: false,
				foregroundStyle: { _ in .gray },
				chartBody: { series, _, time, iaq in
					if let iaq {
						let iaqEnum = Iaq.getIaq(for: Int(iaq))
						PointMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, Float(iaq))
						)
						.symbol(Circle())
						.foregroundStyle(iaqEnum.color)
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, Float(iaq))
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Lux
			MetricsChartSeries(
				id: "lux",
				keyPath: \.lux,
				name: "Lux",
				abbreviatedName: "Lux",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.cyan.lighter(componentDelta: 0.3)), .cyan],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, lux in
					if let lux {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, lux)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// White Lux
			MetricsChartSeries(
				id: "whiteLux",
				keyPath: \.whiteLux,
				name: "White Lux",
				abbreviatedName: "White",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.cyan.lighter(componentDelta: 0.5)), Color(UIColor.cyan.lighter(componentDelta: 0.2))],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, lux in
					if let lux {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, lux)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// UV Lux
			MetricsChartSeries(
				id: "uvLux",
				keyPath: \.uvLux,
				name: "UV Lux",
				abbreviatedName: "UV",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.systemIndigo.lighter(componentDelta: 0.4)), Color(UIColor.systemIndigo.lighter(componentDelta: 0.2))],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, lux in
					if let lux {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, lux)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// IR Lux
			MetricsChartSeries(
				id: "irLux",
				keyPath: \.irLux,
				name: "IR Lux",
				abbreviatedName: "IR",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.red.darker(componentDelta: 0.5)), .red],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, lux in
					if let lux {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, lux)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Radiation
			MetricsChartSeries(
				id: "radiation",
				keyPath: \.radiation,
				name: "Radiation",
				abbreviatedName: "☢️",
				minumumYAxisSpan: 20.0,
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.orange.darker(componentDelta: 0.4)), .orange],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, radiation in
					if let radiation {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, radiation)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Combined Wind Speed and Direction Series Configuration -- For use in Chart only
			MetricsChartSeries(
				id: "windSpeedAndDirection",
				keyPath: \.windSpeedAndDirection,
				name: "Wind Speed/Direction",
				abbreviatedName: "Speed/Dir",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.yellow.darker(componentDelta: 0.3)), Color(UIColor.yellow.darker(componentDelta: 0.1))],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, wsad in
					if let wsad {
						// debug data: var wsad = WindSpeedAndDirection(windSpeed:Float.random(in:0...25), windDirection: Int32.random(in:0..<3)*90 )
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, wsad.windSpeed)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
						PointMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, wsad.windSpeed)
						)
						.symbol {
							if let wd = wsad.windDirection {
								Image(systemName: "location.north.circle.fill")
									.symbolRenderingMode(.palette)
									.foregroundStyle(Color.white, Color(UIColor.yellow.darker(componentDelta: 0.3)))
									.rotationEffect(
										.degrees(Double(wd)))
							}
						}.foregroundStyle(.yellow)
					}
				}),

			// Rainfaill 1-hour
			MetricsChartSeries(
				id: "rainfall1H",
				keyPath: \.rainfall1H,
				name: "Rainfall 1H",
				abbreviatedName: "Rain 1H",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.systemBlue.darker(componentDelta: 0.5)), .blue],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, rainfall in
					if let rainfall {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, rainfall)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Rainfaill 24-hour
			MetricsChartSeries(
				id: "rainfall24H",
				keyPath: \.rainfall24H,
				name: "Rainfall 24H",
				abbreviatedName: "Rain 24H",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.systemBlue.darker(componentDelta: 0.5)), .cyan],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, rainfall in
					if let rainfall {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, rainfall)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Weight
			MetricsChartSeries(
				id: "weight",
				keyPath: \.weight,
				name: "Weight",
				abbreviatedName: "kg",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.systemPink.darker(componentDelta: 0.5)), .pink],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, weight in
					if let weight {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, weight)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Distance
			MetricsChartSeries(
				id: "distance",
				keyPath: \.distance,
				name: "Distance",
				abbreviatedName: "Dist",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.systemTeal.darker(componentDelta: 0.7)), Color(UIColor.systemTeal)],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, distance in
					if let distance {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, distance)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Soil Temperature
			MetricsChartSeries(
				id: "soilTemperature",
				keyPath: \.soilTemperature,
				name: "Soil Temperature",
				abbreviatedName: "Soil Temp",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.brown.darker(componentDelta: 0.4)), .brown],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, soilTemp in
					if let soilTemp {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, soilTemp)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				}),

			// Soil Temperature
			MetricsChartSeries(
				id: "soilMoisture",
				keyPath: \.soilMoisture,
				name: "Soil Moisture",
				abbreviatedName: "Moist",
				visible: false,
				foregroundStyle: { _ in
						.linearGradient(
							colors: [Color(UIColor.blue.darker(componentDelta: 0.4)), .brown],
							startPoint: .bottom, endPoint: .top
						)
				},
				chartBody: { series, _, time, soilMoisture in
					if let soilMoisture {
						LineMark(
							x: .value("Time", time),
							y: .value(series.abbreviatedName, soilMoisture)
						)
						.interpolationMethod(.catmullRom)
						.foregroundStyle(by: .value("Series", series.abbreviatedName))
						.lineStyle(StrokeStyle(lineWidth: 4))
						.alignsMarkStylesWithPlotArea()
					}
				})
		])
	}
}

// Extension to combine windspeed and direction into one attribute for rendering
// for rendering on the chart.
@objc class WindSpeedAndDirection: NSObject, Plottable, Comparable {

	let windSpeed: Float
	let windDirection: Int32?
	init(windSpeed: Float, windDirection: Int32?) {
		self.windSpeed = windSpeed
		self.windDirection = windDirection
	}

	// Plottable Conformance
	required init?(primitivePlottable: Float) { nil }
	var primitivePlottable: Float { windSpeed  }

	static func < (lhs: WindSpeedAndDirection, rhs: WindSpeedAndDirection) -> Bool {
		lhs.windSpeed < rhs.windSpeed
	}
}

@objc extension TelemetryEntity {
	var windSpeedAndDirection: WindSpeedAndDirection? {
		guard let windSpeed = self.windSpeed else { return nil }

		return WindSpeedAndDirection(windSpeed: windSpeed, windDirection: self.windDirection)
	}
}

// From: https://github.com/meshtastic/Meshtastic-Apple/pull/1013/commits/bc932567c742c8fa9fd30752237b10cb762c5ef3
// Set up gradient stops relative to the scale of the temperature chart
func generateStops(minTemp: Double, maxTemp: Double, tempUnit: UnitTemperature, opacity: Double) -> [Gradient.Stop] {
	var gradientStops = [Gradient.Stop]()

	let stopTargets: [(Double, Color)] = [
		((tempUnit == .celsius ? 0 : 32), .blue),
		((tempUnit == .celsius ? 20 : 68), .yellow),
		((tempUnit == .celsius ? 30 : 86), .orange),
		((tempUnit == .celsius ? 55 : 125), .red)
	]
	for (stopValue, color) in stopTargets {
		let stopLocation = transform(stopValue, from: minTemp...maxTemp, to: 0...1)
		gradientStops.append(Gradient.Stop(color: color.opacity(opacity), location: stopLocation))
	}
	return gradientStops
}

// Map inputRange to outputRange
func transform<T: FloatingPoint>(_ input: T, from inputRange: ClosedRange<T>, to outputRange: ClosedRange<T>) -> T {
	// need to determine what that value would be in (to.low, to.high)
	// difference in output range / difference in input range = slope
	let slope = (outputRange.upperBound - outputRange.lowerBound) / (inputRange.upperBound - inputRange.lowerBound)
	// slope * normalized input + output lower
	let output = slope * (input - inputRange.lowerBound) + outputRange.lowerBound
	return output
}
