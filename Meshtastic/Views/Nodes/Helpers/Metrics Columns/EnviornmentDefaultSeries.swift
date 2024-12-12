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
				keyPath: \.temperature,
				name: "Temperature",
				abbreviatedName: "Temp",
				chartBody: { series, time, temperature in
					AreaMark(
						x: .value("Time", time),
						y: .value(
							series.name, temperature.localeTemperature()),
						series: .value("Metric", series.name),
						stacking: .unstacked
					)
					.interpolationMethod(.cardinal)
					.foregroundStyle(
						.linearGradient(
							colors: [.blue, .yellow, .orange, .red, .red],
							startPoint: .bottom, endPoint: .top
						)
						.opacity(0.6)
					)
					.alignsMarkStylesWithPlotArea()
					.accessibilityHidden(true)
					LineMark(
						x: .value("Time", time),
						y: .value(
							series.name, temperature.localeTemperature()),
						series: .value("Metric", series.name)
					)
					.interpolationMethod(.cardinal)
					.foregroundStyle(
						.linearGradient(
							colors: [.blue, .yellow, .orange, .red, .red],
							startPoint: .bottom, endPoint: .top
						)
					)
					.lineStyle(StrokeStyle(lineWidth: 4))
					.alignsMarkStylesWithPlotArea()
				}),

			// Relative Humidity Series Configuration
			MetricsChartSeries(
				keyPath: \.relativeHumidity,
				name: "Relative Humidity",
				abbreviatedName: "Hum",
				chartBody: { series, time, humidity in
					LineMark(
						x: .value("Time", time),
						y: .value(series.name, humidity),
						series: .value("Metric", series.name)
					)
					.interpolationMethod(.cardinal)
					.foregroundStyle(
						.linearGradient(
							colors: [.gray, .blue],
							startPoint: .bottom, endPoint: .top
						)
					)
					.lineStyle(StrokeStyle(lineWidth: 4))
					.alignsMarkStylesWithPlotArea()
				}),

			// Barometric Pressure Series Configuration
			MetricsChartSeries(
				keyPath: \.barometricPressure,
				name: "Barometric Pressure",
				abbreviatedName: "Bar",
				visible: false,
				chartBody: { series, time, pressure in
					LineMark(
						x: .value("Time", time),
						y: .value(series.name, pressure),
						series: .value("Metric", series.name)
					)
					.interpolationMethod(.cardinal)
					.foregroundStyle(
						.linearGradient(
							colors: [.gray, .green],
							startPoint: .bottom, endPoint: .top
						)
					)
					.lineStyle(StrokeStyle(lineWidth: 4))
					.alignsMarkStylesWithPlotArea()

				}),

			// Indoor Air Quality Series Configuration
			MetricsChartSeries(
				keyPath: \.iaq,
				name: "Indoor Air Quality",
				abbreviatedName: "IAQ",
				visible: false,
				chartBody: { series, time, iaq in
					let iaqEnum = Iaq.getIaq(for: Int(iaq))
					PointMark(
						x: .value("Time", time),
						y: .value(series.name, Float(iaq))
					)
					.symbol(Circle())
					.foregroundStyle(iaqEnum.color)
				}),

			// Combined Wind Speed and Direction Series Configuration -- For use in Chart only
			MetricsChartSeries(
				keyPath: \.windSpeedAndDirection,
				name: "Wind Speed/Direction",
				abbreviatedName: "Speed/Dir",
				visible: false,
				chartBody: { series, time, wsad in
					// debug data: var wsad = WindSpeedAndDirection(windSpeed:Float.random(in:0...25), windDirection: Int32.random(in:0..<3)*90 )
					LineMark(
						x: .value("Time", time),
						y: .value(series.name, wsad.windSpeed),
						series: .value("Metric", series.name)
					)
					.interpolationMethod(.cardinal)
					.foregroundStyle(
						.linearGradient(
							colors: [Color(UIColor.yellow.darker()), .yellow],
							startPoint: .bottom, endPoint: .top
						)
					)
					.lineStyle(StrokeStyle(lineWidth: 4))
					.alignsMarkStylesWithPlotArea()
					PointMark(
						x: .value("Time", time),
						y: .value(series.name, wsad.windSpeed)
					)
					.symbol {
						Image(systemName: "location.north.circle.fill")
							.symbolRenderingMode(.palette)
							.foregroundStyle(Color.white, Color.yellow)
							.rotationEffect(
								.degrees(Double(wsad.windDirection)))
					}.foregroundStyle(.yellow)
				})
		])
	}
}

// Extension to combine windspeed and direction into one attribute for rendering
// for rendering on the chart.
@objc class WindSpeedAndDirection: NSObject {
	let windSpeed: Float
	let windDirection: Int32
	init(windSpeed: Float, windDirection: Int32) {
		self.windSpeed = windSpeed
		self.windDirection = windDirection
	}
}
@objc extension TelemetryEntity {
	var windSpeedAndDirection: WindSpeedAndDirection {
		return WindSpeedAndDirection(
			windSpeed: self.windSpeed, windDirection: self.windDirection)
	}
}
