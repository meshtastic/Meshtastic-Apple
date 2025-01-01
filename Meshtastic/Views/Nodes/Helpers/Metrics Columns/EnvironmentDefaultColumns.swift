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
					} ?? Text("--")
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
						Text("\(String(format: "%.0f", $0))%")
					} ?? Text("--")
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
						if (UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac) {
							Text("\(String(format: "%.1f hPa", $0))")
						} else {
							Text("\(String(format: "%.1f", $0))")
						}
					} ?? Text("--")
				}),
		
			// Distance sensor, often used for water level
			MetricsTableColumn(
				id: "distance",
				keyPath: \.distance,
				name: "Distance",
				abbreviatedName: "Dist",
				minWidth: 30, maxWidth: 50,
				visible: false,
				tableBody: { _, distance in
					distance.map {
						if (UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac) {
							Text("\(String(format: "%.1f mm", $0))")
						} else {
							Text("\(String(format: "%.1f", $0))")
						}
					} ?? Text("--")
				}),
			
//			// Gas Resistance - This is a raw sensor value used for IAQ.
//			// Commented out as better represented in the IAQ value.
//			MetricsTableColumn(
//				id: "gasResistance",
//				keyPath: \.gasResistance,
//				name: "Gas Resistance",
//				abbreviatedName: "Gas Res",
//				minWidth: 30, maxWidth: 50,
//				visible: false,
//				tableBody: { _, resistance in
//					if (UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac) {
//						Text("\(String(format: "%.1f MΩ", resistance))")
//					} else {
//						Text("\(String(format: "%.1f", resistance))")
//					}
//				}),
//		
//			// Indoor Air Quality Series Configuration
//			MetricsTableColumn(
//				keyPath: \.iaq,
//				name: "Indoor Air Quality",
//				abbreviatedName: "IAQ",
//				minWidth: 30, maxWidth: 50,
//				tableBody: { _, iaq in
//					IndoorAirQuality(iaq: Int(iaq), displayMode: .dot)
//				}),

			// Various Lux
			MetricsTableColumn(
				id: "lux",
				keyPath: \.lux,
				name: "Lux",
				abbreviatedName: "Lux",
				minWidth: 30, maxWidth: 50,
				visible: false,
				tableBody: { _, lux in
					lux.map {
						Text("\(String(format: "%.1f", $0))")
					} ?? Text("--")
				}),
			
			MetricsTableColumn(
				id: "whiteLux",
				keyPath: \.whiteLux,
				name: "White Lux",
				abbreviatedName: "White",
				minWidth: 30, maxWidth: 50,
				visible: false,
				tableBody: { _, lux in
					lux.map {
						Text("\(String(format: "%.1f", $0))")
					} ?? Text("--")
				}),
	
			MetricsTableColumn(
				id: "uvLux",
				keyPath: \.uvLux,
				name: "UV Lux",
				abbreviatedName: "UV",
				minWidth: 30, maxWidth: 50,
				visible: false,
				tableBody: { _, lux in
					lux.map {
						Text("\(String(format: "%.1f", $0))")
					} ?? Text("--")
				}),
		
			MetricsTableColumn(
				id: "irLux",
				keyPath: \.irLux,
				name: "IR Lux",
				abbreviatedName: "IR",
				minWidth: 30, maxWidth: 50,
				visible: false,
				tableBody: { _, lux in
					lux.map {
						Text("\(String(format: "%.1f", $0))")
					} ?? Text("--")
				}),

			// Radiation
			MetricsTableColumn(
				id: "radiation",
				keyPath: \.radiation,
				name: "Radiation",
				abbreviatedName: "☢️",
				minWidth: 30, maxWidth: 50,
				visible: false,
				tableBody: { _, radiation in
					radiation.map {
						if (UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac) {
							Text("\(String(format: "%.1f µR/h", $0))")
						} else {
							Text("\(String(format: "%.1f", $0))")
						}
					} ?? Text("--")
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
						Text("--")
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
									numberFormatStyle: .number.precision(
										.fractionLength(0))))
						)
					} ?? Text("--")
				}),
			
			//Weight
			MetricsTableColumn(
				id: "weight",
				keyPath: \.weight,
				name: "Weight",
				abbreviatedName: "kg",
				minWidth: 30, maxWidth: 60,
				visible: false,
				tableBody: { _, weight in
					weight.map {
						let weight = Measurement(
							value: Double($0), unit: UnitMass.kilograms)
						return Text(
							weight.formatted(
								.measurement(
									width: .abbreviated,
									numberFormatStyle: .number.precision(
										.fractionLength(0))))
						)
					} ?? Text("--")
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
