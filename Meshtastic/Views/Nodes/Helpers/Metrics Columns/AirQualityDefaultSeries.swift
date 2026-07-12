//
//  AirQualityDefaultSeries.swift
//  Meshtastic
//
//  Default chart configuration for the AirQualityMetricsLog view (issue #2040).
//

import Charts
import Foundation
import SwiftUI

// Builds a line-mark series for a particulate-matter concentration (µg/m³). PM values
// arrive as UInt32, mirroring the soilMoisture series' handling of an unsigned integer.
private func pmSeries(id: String, keyPath: KeyPath<TelemetryEntity, UInt32?>, name: String, abbreviatedName: String, colors: [Color], visible: Bool = true) -> MetricsChartSeries {
	MetricsChartSeries(
		id: id,
		keyPath: keyPath,
		name: name,
		abbreviatedName: abbreviatedName,
		visible: visible,
		foregroundStyle: { _ in
			.linearGradient(colors: colors, startPoint: .bottom, endPoint: .top)
		},
		chartBody: { series, _, time, value in
			if let value {
				LineMark(
					x: .value("Time", time),
					y: .value(series.abbreviatedName, value)
				)
				// Linear (not Catmull-Rom): raw PM samples are sparse, and spline smoothing can
				// overshoot between points and imply concentrations that were never measured.
				.interpolationMethod(.linear)
				.foregroundStyle(by: .value("Series", series.abbreviatedName))
				.lineStyle(series.strokeStyle)
				.alignsMarkStylesWithPlotArea()
			}
		})
}

// This is the default configuration used by the AirQualityMetricsLog view for the chart
extension MetricsSeriesList {
	static var airQualityDefaultChartSeries: MetricsSeriesList {
		MetricsSeriesList(persistenceKey: "airQuality", series: [
			pmSeries(id: "pm25Standard", keyPath: \.pm25Standard, name: "PM2.5 (Standard)", abbreviatedName: "PM2.5",
					 colors: [Color(UIColor.systemRed.darker(componentDelta: 0.4)), .red]),
			pmSeries(id: "pm10Standard", keyPath: \.pm10Standard, name: "PM1.0 (Standard)", abbreviatedName: "PM1.0",
					 colors: [Color(UIColor.systemOrange.darker(componentDelta: 0.4)), .orange]),
			pmSeries(id: "pm100Standard", keyPath: \.pm100Standard, name: "PM10 (Standard)", abbreviatedName: "PM10",
					 colors: [Color(UIColor.systemPurple.darker(componentDelta: 0.4)), .purple]),
			pmSeries(id: "pm25Environmental", keyPath: \.pm25Environmental, name: "PM2.5 (Environmental)", abbreviatedName: "PM2.5 Env",
					 colors: [Color(UIColor.systemPink.darker(componentDelta: 0.4)), .pink], visible: false),
			pmSeries(id: "pm10Environmental", keyPath: \.pm10Environmental, name: "PM1.0 (Environmental)", abbreviatedName: "PM1.0 Env",
					 colors: [Color(UIColor.systemYellow.darker(componentDelta: 0.4)), .yellow], visible: false),
			pmSeries(id: "pm100Environmental", keyPath: \.pm100Environmental, name: "PM10 (Environmental)", abbreviatedName: "PM10 Env",
					 colors: [Color(UIColor.systemIndigo.darker(componentDelta: 0.4)), .indigo], visible: false)
		])
	}
}
