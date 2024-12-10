//
//  EnvironmentMetricsColumnDefaults.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/24.
//

import Foundation
import SwiftUI
import Charts

extension MetricsColumnConfiguration {
	static var environmentDefaults: MetricsColumnConfiguration { MetricsColumnConfiguration(columns: [
		
		// Temperature Series Configuration
		MetricsColumnConfigurationEntry(attribute: "temperature", keyPath: \.temperature,
										columnName: "Temperature",
										abbreviatedColumnName: "Temp",
										minWidth: 30, maxWidth: 50,
										showInChart: true,
										tableBody: { _, temp in
											Text(temp.formattedTemperature())
												.font(.caption)
										}, chartBody: { config, time, temperature in
											AreaMark(
												x: .value("Time", time),
												y: .value(config.columnName, temperature.localeTemperature()),
												series: .value("Metric", config.columnName), stacking: .unstacked
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
												y: .value(config.columnName, temperature.localeTemperature()),
												series: .value("Metric", config.columnName)
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
		MetricsColumnConfigurationEntry(attribute: "relativeHumidity", keyPath: \.relativeHumidity,
										columnName: "Relative Humidity",
										abbreviatedColumnName: "Hum",
										minWidth: 30, maxWidth: 50,
										tableBody: { _, humidity in
											Text("\(String(format: "%.0f", humidity))%")
												.font(.caption)
										}, chartBody: { config, time, humidity in
											LineMark(
												x: .value("Time", time),
												y: .value(config.columnName, humidity),
												series: .value("Metric", config.columnName)
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
		MetricsColumnConfigurationEntry(attribute: "barometricPressure", keyPath: \.barometricPressure,
										columnName: "Barometric Pressure",
										abbreviatedColumnName: "Bar",
										minWidth: 30, maxWidth: 60,
										tableBody: { _, pressure in
											Text("\(String(format: "%.1f", pressure))")
												.font(.caption)
										}, chartBody: { config, time, pressure in
											LineMark(
												x: .value("Time", time),
												y: .value(config.columnName, pressure),
												series: .value("Metric", config.columnName)
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
		MetricsColumnConfigurationEntry(attribute: "iaq", keyPath: \.iaq,
										columnName: "Indoor Air Quality",
										abbreviatedColumnName: "IAQ",
										minWidth: 30, maxWidth: 70,
										tableBody: { _, iaq in
											IndoorAirQuality(iaq: Int(iaq), displayMode: .dot)
												.font(.caption)
										}, chartBody: { config, time, iaq in
											PointMark(x: .value("Time", time),
													  y: .value(config.columnName, 0.0))
											.symbol(Circle())
											.foregroundStyle(Iaq.getIaq(for: Int(iaq)).color)
										}),

		// Wind Direction Series Configuration
		MetricsColumnConfigurationEntry(attribute: "windDirection", keyPath: \.windDirection,
										availability: .table,
										columnName: "Wind Direction",
										abbreviatedColumnName: "Dir",
										minWidth: 30, maxWidth: 40,
										tableBody: { _, wind in
											Text(cardinalValue(from: Double(wind)))
												.font(.caption)
										}, chartBody: { _, _, _ in
											
										}),

		// Wind Speed Series Configuration
		MetricsColumnConfigurationEntry(attribute: "windSpeed", keyPath: \.windSpeed,
										availability: .table,
										columnName: "Wind Speed",
										abbreviatedColumnName: "Wind",
										minWidth: 30, maxWidth: 40,
										tableBody: { _, speed in
											let windSpeed = Measurement(value: Double(speed), unit: UnitSpeed.kilometersPerHour)
											Text(windSpeed.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
												.font(.caption)
										}, chartBody: { _, _, _ in
											
										}),
		
		// Combined Wind Speed and Direction Series Configuration -- For use in Chart only
		MetricsColumnConfigurationEntry(attribute: "windSpeedAndDirection", keyPath: \.windSpeedAndDirection,
										availability: .chart,
										columnName: "Wind Speed/Direction",
										abbreviatedColumnName: "Speed/Dir",
										minWidth: 30, maxWidth: 40,
										tableBody: { _, _ in
											EmptyView()
										}, chartBody: { config, time, wsad in
											var wsad = (Float.random(in:0...25), Int32.random(in:0..<3)*90 )
											LineMark(
												x: .value("Time", time),
												y: .value(config.columnName, wsad.0),
												series: .value("Metric", config.columnName)
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
											PointMark(x: .value("Time", time),
													  y: .value(config.columnName, wsad.0))
											.symbol {
												Image(systemName: "location.north.circle.fill")
													.symbolRenderingMode(.palette)
													.foregroundStyle(Color.white, Color.yellow)
													.rotationEffect(.degrees(Double(wsad.1)))
											}.foregroundStyle(.yellow)

										}),

		
		// Timestamp Series Configuration -- for use in table only
		MetricsColumnConfigurationEntry(attribute: "time", keyPath: \.time,
										availability: .table,
										columnName: "Timestamp",
										abbreviatedColumnName: "Time",
										tableBody: { _, time in
											let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
											let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
											Text(time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized)
												.font(.caption)
										}, chartBody: { _, _, _ in
											
										})
		])
	}
}


extension TelemetryEntity {
	var windSpeedAndDirection: (Float, Int32) {
		return (self.windSpeed, self.windDirection)
	}
}
