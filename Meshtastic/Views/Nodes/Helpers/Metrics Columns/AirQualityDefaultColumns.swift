//
//  AirQualityDefaultColumns.swift
//  Meshtastic
//
//  Default table configuration for the AirQualityMetricsLog view (issue #2040).
//

import Charts
import Foundation
import SwiftUI

// Renders a particulate-matter concentration (µg/m³). PM values arrive as UInt32,
// mirroring the soilMoisture column's handling of an optional unsigned integer.
private func pmColumn(id: String, keyPath: KeyPath<TelemetryEntity, UInt32?>, name: String, abbreviatedName: String, visible: Bool = true) -> MetricsTableColumn {
	MetricsTableColumn(
		id: id,
		keyPath: keyPath,
		name: name,
		abbreviatedName: abbreviatedName,
		minWidth: 30, maxWidth: 60,
		visible: visible,
		tableBody: { _, value in
			value.map {
				if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
					Text(verbatim: "\($0.formatted(.number.grouping(.never))) µg/m³")
				} else {
					Text($0.formatted(.number.grouping(.never)))
				}
			} ?? Text(verbatim: Constants.nilValueIndicator)
		})
}

// This is the default configuration used by the AirQualityMetricsLog view for the table
extension MetricsColumnList {
	static var airQualityDefaultColumns: MetricsColumnList {
		MetricsColumnList(persistenceKey: "airQuality", columns: [
			pmColumn(id: "pm25Standard", keyPath: \.pm25Standard, name: "PM2.5 (Standard)", abbreviatedName: "PM2.5"),
			pmColumn(id: "pm10Standard", keyPath: \.pm10Standard, name: "PM1.0 (Standard)", abbreviatedName: "PM1.0"),
			pmColumn(id: "pm100Standard", keyPath: \.pm100Standard, name: "PM10 (Standard)", abbreviatedName: "PM10"),
			pmColumn(id: "pm25Environmental", keyPath: \.pm25Environmental, name: "PM2.5 (Environmental)", abbreviatedName: "PM2.5 Env", visible: false),
			pmColumn(id: "pm10Environmental", keyPath: \.pm10Environmental, name: "PM1.0 (Environmental)", abbreviatedName: "PM1.0 Env", visible: false),
			pmColumn(id: "pm100Environmental", keyPath: \.pm100Environmental, name: "PM10 (Environmental)", abbreviatedName: "PM10 Env", visible: false),

			// Timestamp Series Configuration -- for use in table only
			MetricsTableColumn(
				id: "time",
				keyPath: \.time,
				name: "Timestamp",
				abbreviatedName: "Time",
				minWidth: 140.0, maxWidth: 2000.0,
				tableBody: { _, time in
					Text(
						time?.formatted(date: .numeric, time: .shortened)
						?? "Unknown Age".localized
					)
				})
		])
	}
}
