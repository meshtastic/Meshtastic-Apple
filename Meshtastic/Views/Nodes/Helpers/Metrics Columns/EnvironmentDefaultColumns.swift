//
//  EnvironmentDefaultColumns.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/10/24.
//

import Charts
import Foundation
import SwiftUI

// This is the default configuration used by the EnvironmentMetricsLog view for the table
extension MetricsColumnList {
	static var environmentDefaultColumns: MetricsColumnList {
		MetricsColumnList(columns: [
			// Temperature Series Configuration
			MetricsTableColumn(
				id: "temperature",
				keyPath: \.temperature,
				name: "Temperature",
				abbreviatedName: "Temp",
				minWidth: 30, maxWidth: 45,
				tableBody: { _, temp in
					temp.map {
						Text($0.formattedTemperature())
					} ?? Text(verbatim: Constants.nilValueIndicator)
				}),

			// Relative Humidity Series Configuration
			MetricsTableColumn(
				id: "relativeHumidity",
				keyPath: \.relativeHumidity,
				name: "Relative Humidity",
				abbreviatedName: "Hum",
				minWidth: 30, maxWidth: 45,
				tableBody: { _, humidity in
					humidity.map {
						Text("\($0.formatted(.number.grouping(.never).precision(.fractionLength(0))))%")
					} ?? Text(verbatim: Constants.nilValueIndicator)
				}),

			// Barometric Pressure Series Configuration
			MetricsTableColumn(
				id: "barometricPressure",
				keyPath: \.barometricPressure,
				name: "Barometric Pressure",
				abbreviatedName: "Bar",
				minWidth: 30, maxWidth: 50,
				tableBody: { _, pressure in
					pressure.map {
						if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
							// Text("\(String(format: "%.1f hPa", $0))")
							Text(Measurement(value: Double($0), unit: UnitPressure.hectopascals), format: .measurement(width: .abbreviated, numberFormatStyle: .number.grouping(.never).precision(.fractionLength(1))))
						} else {
							// Text("\(String(format: "%.1f", $0))")
							Text($0, format: .number.grouping(.never).precision(.fractionLength(1)))
						}
					} ?? Text(verbatim: Constants.nilValueIndicator)
				}),

			// Indoor Air Quality Series Configuration
			MetricsTableColumn(
				id: "iaq",
				keyPath: \.iaq,
				name: "Indoor Air Quality",
				abbreviatedName: "IAQ",
				minWidth: 30, maxWidth: 50,
				tableBody: { _, iaq in
					if let iaq {
						IndoorAirQuality(iaq: Int(iaq), displayMode: .dot)
					} else {
						Text(verbatim: Constants.nilValueIndicator)
					}
				}),

			// Wind Direction Series Configuration
			MetricsTableColumn(
				id: "windDirection",
				keyPath: \.windDirection,
				name: "Wind Direction",
				abbreviatedName: "Dir",
				minWidth: 30, maxWidth: 40,
				visible: false,
				tableBody: { _, wind in
					HStack(spacing: 1.0) {
						// debug data: let wind = Double.random(in: 0..<360.0)
						if let wind {
							HStack(spacing: 1.0) {
								// debug data: let wind = Double.random(in: 0..<360.0)
								let wind = Double(wind)
								Image(systemName: "location.north")
									.imageScale(.small)
									.scaleEffect(0.9, anchor: .center)
									.rotationEffect(.degrees(wind))
									.foregroundStyle(.blue)
								if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
									Text(cardinalValue(from: wind))
								} else {
									Text(abbreviatedCardinalValue(from: wind))
								}
							}
						} else {
							Text(verbatim: Constants.nilValueIndicator)
						}
					}
				}),

			// Wind Speed Series Configuration
			MetricsTableColumn(
				id: "windSpeed",
				keyPath: \.windSpeed,
				name: "Wind Speed",
				abbreviatedName: "Wind",
				minWidth: 30, maxWidth: 60,
				visible: false,
				tableBody: { _, speed in
					speed.map {
						let windSpeed = Measurement(
							value: Double($0), unit: UnitSpeed.kilometersPerHour)
						return Text(
							windSpeed.formatted(
								.measurement(
									width: .abbreviated,
									numberFormatStyle: .number.grouping(.never)
													.precision(.fractionLength(0))))
						)
					} ?? Text(verbatim: Constants.nilValueIndicator)
				}),

			// Timestamp Series Configuration -- for use in table only
			MetricsTableColumn(
				id: "time",
				keyPath: \.time,
				name: "Timestamp",
				abbreviatedName: "Time",
				minWidth: 140.0, maxWidth: 2000.0,
				tableBody: { _, time in
					let localeDateFormat = DateFormatter.dateFormat(
						fromTemplate: "yyMMddjmma", options: 0,
						locale: Locale.current)
					let dateFormatString =
						(localeDateFormat ?? "MM/dd/YY j:mma")
						.replacingOccurrences(of: ",", with: "")
					Text(
						time?.formattedDate(format: dateFormatString)
							?? "unknown.age".localized
					)
				})
		])
	}
}
