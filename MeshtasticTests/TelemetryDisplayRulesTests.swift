//
//  TelemetryDisplayRulesTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//

import Foundation
import Testing
@testable import Meshtastic

/// The sensor display rules from design#53.
@Suite("Telemetry display rules")
struct TelemetryDisplayRulesTests {

	// MARK: - Axes

	@Test("Pressure near sea level shows 950 to 1050 hPa")
	func pressureAtSeaLevel() {
		#expect(MetricsAxis.pressure.range(for: [1008, 1013, 1021]) == 950...1050)
	}

	@Test("Pressure at altitude slides the 100 hPa window down instead of clipping")
	func pressureAtAltitude() {
		#expect(MetricsAxis.pressure.range(for: [838, 845]) == 838...938)
	}

	@Test("High pressure slides the window up")
	func pressureHigh() {
		#expect(MetricsAxis.pressure.range(for: [1040, 1062]) == 962...1062)
	}

	@Test("Pressure spanning more than 100 hPa widens to the readings")
	func pressureWide() {
		let range = MetricsAxis.pressure.range(for: [820, 1010])
		#expect(range.lowerBound < 820)
		#expect(range.upperBound > 1010)
	}

	@Test("Temperature is padded around its readings, not pinned to zero")
	func temperaturePadded() {
		let range = MetricsAxis.temperature.range(for: [18, 24])
		#expect(range.lowerBound > 0)
		#expect(range.contains(18) && range.contains(24))
	}

	@Test("Humidity runs 0 to 100")
	func humidityFixed() {
		#expect(MetricsAxis.percent.range(for: [40, 62]) == 0...100)
	}

	@Test("A zero-based axis puts zero just above the bottom edge")
	func zeroBasedOffset() {
		let range = MetricsAxis.zeroBased("pm").range(for: [0, 20])
		#expect(range.lowerBound < 0)
		#expect(range.lowerBound > -5)
		#expect(range.upperBound > 20)
	}

	// MARK: - Chart groups

	private func reading(temperature: Float? = nil, humidity: Float? = nil, lux: Float? = nil) -> TelemetryEntity {
		let row = TelemetryEntity()
		row.metricsType = 1
		row.time = Date()
		row.temperature = temperature
		row.relativeHumidity = humidity
		row.lux = lux
		return row
	}

	@Test("Temperature, humidity and lux each get their own chart")
	func separateCharts() {
		let list = MetricsSeriesList(series: MetricsSeriesList.environmentDefaultChartSeries.series)
		list.series.forEach { $0.visible = ["temperature", "relativeHumidity", "dewPoint", "lux"].contains($0.id) }
		let groups = list.chartGroups(forData: [reading(temperature: 20, humidity: 50, lux: 3_000)])
		#expect(groups.map(\.axis.id) == ["temperature", "percent", "lux"])
		// Dew point shares the temperature chart.
		#expect(groups.first?.series.map(\.id) == ["temperature", "dewPoint"])
	}

	@Test("A series with no readings gets no chart")
	func noReadingsNoChart() {
		let list = MetricsSeriesList(series: MetricsSeriesList.environmentDefaultChartSeries.series)
		list.series.forEach { $0.visible = ["temperature", "relativeHumidity", "dewPoint"].contains($0.id) }
		let groups = list.chartGroups(forData: [reading(lux: 3_000)])
		#expect(groups.isEmpty)
	}

	@Test("CO2 gets its own chart, apart from particulates")
	func co2Separate() {
		let list = MetricsSeriesList(series: MetricsSeriesList.airQualityDefaultChartSeries.series)
		let row = TelemetryEntity()
		row.metricsType = 3
		row.time = Date()
		row.pm25Standard = 9
		row.co2 = 850
		let groups = list.chartGroups(forData: [row])
		#expect(groups.map(\.axis.id) == ["pm", "co2"])
	}

	// MARK: - CO2 bands

	@Test("CO2 bands follow design#53", arguments: [
		(UInt32(400), Co2Level.good),
		(999, .good),
		(1_000, .stuffy),
		(1_999, .stuffy),
		(2_000, .poor),
		(4_999, .poor),
		(5_000, .unsafe),
		(29_999, .unsafe),
		(30_000, .evacuate)
	])
	func co2Bands(ppm: UInt32, level: Co2Level) {
		#expect(Co2Level.level(for: ppm) == level)
	}

	// MARK: - Power channels

	@Test("A blank power channel label falls back to Channel N")
	func powerChannelLabels() {
		let labels = ["Solar", "  ", "Load"]
		#expect(PowerChannelLabel.name(0, in: labels) == "Solar")
		#expect(PowerChannelLabel.name(1, in: labels) == String(format: "Channel %d".localized, 2))
		#expect(PowerChannelLabel.name(6, in: labels) == String(format: "Channel %d".localized, 7))
	}

	@Test("Power CSV has a voltage and current column for each of the eight channels")
	func powerCsvHeader() {
		let row = TelemetryEntity()
		row.metricsType = 2
		row.powerCh8Voltage = 5
		let lines = telemetryToCsvFile(telemetry: [row], metricsType: 2).split(separator: "\n")
		#expect(lines.first?.contains("Channel 8 Current") == true)
		#expect(lines.first?.split(separator: ",").count == 17)
		#expect(lines.last?.split(separator: ",", omittingEmptySubsequences: false).count == 17)
	}

	@Test("Each power CSV value lands under its own channel's header, with a decimal point")
	func powerCsvColumns() throws {
		let row = TelemetryEntity()
		row.metricsType = 2
		row.powerCh1Voltage = 12.5
		row.powerCh1Current = 101.5
		row.powerCh3Current = 0
		row.powerCh8Voltage = 3.25
		row.powerCh8Current = 808.5
		let lines = telemetryToCsvFile(telemetry: [row], metricsType: 2).split(separator: "\n")
		let header = try #require(lines.first).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
		let values = try #require(lines.last).split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
		let byHeader = Dictionary(uniqueKeysWithValues: zip(header, values))
		#expect(byHeader["Channel 1 Voltage"] == "12.5")
		#expect(byHeader["Channel 1 Current"] == "101.5")
		#expect(byHeader["Channel 2 Voltage"] == "")
		// A reported zero is a reading, not a blank.
		#expect(byHeader["Channel 3 Current"] == "0")
		#expect(byHeader["Channel 8 Voltage"] == "3.25")
		#expect(byHeader["Channel 8 Current"] == "808.5")
	}
}
