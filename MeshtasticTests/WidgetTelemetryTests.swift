//
//  WidgetTelemetryTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
import Foundation
import Testing
@testable import Meshtastic

/// The Telemetry widget (design#179): which nodes and metrics it offers, how a
/// reading reads, when it's old, and how the large size pages.
@Suite("Widget telemetry")
struct WidgetTelemetryTests {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	private func snapshot(nodes: [NodeSnapshot], radio: Int64? = 1) -> WidgetSnapshot {
		WidgetSnapshot(
			generatedAt: now, connectionState: .connected, radioNodeNum: radio,
			radioLongName: nil, radioShortName: nil, radioBatteryLevel: nil, localStats: nil,
			nodes: nodes, totalNodeCount: nodes.count, unreadChannelMessages: 0,
			unreadDirectMessages: 0, recentMessages: []
		)
	}

	private func node(_ num: Int64, telemetry: TelemetrySnapshot? = nil) -> NodeSnapshot {
		var node = NodeSnapshot(
			num: num, longName: "Node \(num)", shortName: "N\(num)", colorSeed: UInt32(num),
			batteryLevel: nil, snr: nil, rssi: nil, signalRating: nil,
			lastHeard: now, isOnline: true, hopsAway: 0,
			latitude: nil, longitude: nil, isFavorite: false
		)
		node.telemetry = telemetry
		return node
	}

	@Test func snapshotsFromBeforeEnvironmentStillDecode() throws {
		let encoded = try JSONEncoder().encode(snapshot(nodes: [node(2)]))
		var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
		var nodes = try #require(object["nodes"] as? [[String: Any]])
		nodes[0].removeValue(forKey: "environment")
		object["nodes"] = nodes
		let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
		#expect(decoded.nodes.first?.telemetry == nil)
	}

	@Test func offersOnlyNodesWithReadingsConnectedRadioFirst() {
		let reading = TelemetrySnapshot(time: now, temperature: 20)
		let nodes = TelemetryNodeQuery.telemetryNodes(in: snapshot(nodes: [
			node(3, telemetry: reading),
			node(2),
			node(1, telemetry: reading)
		]))
		#expect(nodes.map(\.num) == [1, 3])
	}

	@Test func showsEveryReportedReadingLessTheHiddenOnes() {
		let reading = TelemetrySnapshot(time: now, temperature: 20, relativeHumidity: 50, barometricPressure: 1013, lux: 300, soilMoisture: 40, co2: 800)
		#expect(TelemetryMetric.shown(in: reading, hiding: []) == [.temperature, .relativeHumidity, .barometricPressure, .dewPoint, .lux, .soilMoisture, .co2])
		#expect(TelemetryMetric.shown(in: reading, hiding: [.dewPoint, .lux]) == [.temperature, .relativeHumidity, .barometricPressure, .soilMoisture, .co2])
		#expect(TelemetryMetric.shown(in: nil, hiding: []).isEmpty)
	}

	@Test func offersOnlyMetricsTheNodeReported() {
		let reading = TelemetrySnapshot(time: now, relativeHumidity: 50, windSpeed: 3)
		// No dew point without a temperature.
		#expect(reading.reportedMetrics == [.relativeHumidity, .wind])
	}

	@Test func aMissingReadingIsNilAndAZeroIsZero() {
		let reading = TelemetrySnapshot(time: now, lux: 0, soilMoisture: 0)
		#expect(TelemetryMetric.lux.reading(in: reading)?.value == "0")
		#expect(TelemetryMetric.soilMoisture.reading(in: reading)?.value == "0")
		#expect(TelemetryMetric.radiation.reading(in: reading) == nil)
	}

	@Test func temperatureAndPressureAreWholePressureInHectopascals() {
		let reading = TelemetrySnapshot(time: now, temperature: 21.6, barometricPressure: 1013.7)
		let pressure = TelemetryMetric.barometricPressure.reading(in: reading)
		#expect(pressure?.value == "1014")
		#expect(pressure?.unit == "hPa")
		let temperature = TelemetryMetric.temperature.reading(in: reading)
		// Whichever unit the locale uses, the value matches the app's conversion, whole.
		let expected = Float(21.6).localeTemperature().formatted(.number.precision(.fractionLength(0)))
		#expect(temperature?.value == expected)
		#expect(temperature?.unit == "°C" || temperature?.unit == "°F")
	}

	@Test func aNonFiniteReadingIsNoReading() {
		let reading = TelemetrySnapshot(time: now, temperature: .nan)
		#expect(TelemetryMetric.temperature.reading(in: reading) == nil)
		#expect(reading.reportedMetrics.isEmpty)
	}

	@Test func iaqCarriesItsBand() {
		let reading = TelemetrySnapshot(time: now, iaq: 120)
		let iaq = TelemetryMetric.iaq.reading(in: reading)
		#expect(iaq?.value == "120")
		#expect(iaq?.detail == Iaq.lightlyPolluted.description)
		#expect(iaq?.color == Iaq.lightlyPolluted.color)
	}

	@Test func airQualityReadsAsNodeDetailsShowsIt() {
		let reading = TelemetrySnapshot(time: now, pm25Standard: 12, co2: 1240)
		#expect(TelemetryMetric.pm25.reading(in: reading)?.value == "12")
		#expect(TelemetryMetric.pm25.reading(in: reading)?.unit == "µg/m³")
		let co2 = TelemetryMetric.co2.reading(in: reading)
		#expect(co2?.value == "1240")
		#expect(co2?.detail == Co2Level.stuffy.description)
		#expect(reading.reportedMetrics == [.pm25, .co2])
	}

	@Test func powerChannelsUseTheNodesLabels() {
		var names = (1...8).map { "Channel \($0)" }
		names[0] = "Solar"
		let reading = TelemetrySnapshot(
			time: now,
			powerVoltages: [12.6, nil, nil, nil, nil, nil, nil, nil],
			powerCurrents: [310.44, nil, nil, nil, nil, nil, nil, 0],
			powerChannelNames: names
		)
		#expect(TelemetryMetric.power1Voltage.reading(in: reading)?.value == "12.60")
		#expect(TelemetryMetric.power1Current.reading(in: reading)?.value == "310.4")
		#expect(TelemetryMetric.power8Current.reading(in: reading)?.value == "0.0")
		#expect(TelemetryMetric.power2Voltage.reading(in: reading) == nil)
		#expect(TelemetryMetric.power1Voltage.title(in: reading).contains("Solar"))
		#expect(reading.reportedMetrics == [.power1Voltage, .power1Current, .power8Current])
	}

	@Test func extraLargePortraitPagesBeyondSix() {
		let metrics = Array(TelemetryMetric.allCases.prefix(8))
		let size = TelemetryWidgetPage.extraLargePortraitPageSize
		#expect(TelemetryWidgetPage.pageCount(for: 6, pageSize: size) == 1)
		#expect(TelemetryWidgetPage.pageCount(for: 8, pageSize: size) == 2)
		#expect(TelemetryWidgetPage.metrics(metrics, page: 1, pageSize: size) == Array(metrics.suffix(2)))
		// The stored page is shared with the large size; each size wraps it to its own pages.
		#expect(TelemetryWidgetPage.wrap(3, pageCount: 2) == 1)
		#expect(TelemetryWidgetPage.wrap(3, pageCount: 1) == 0)
	}

	@Test func bestFitPicksTheLargestTiles() {
		// A tall widget with six readings: two columns of three beat two columns of four.
		let tall = TelemetryWidgetPage.bestFit(count: 6, in: CGSize(width: 360, height: 640), spacing: 8)
		#expect(tall.columns == 2)
		#expect(tall.rows == 3)
		// One reading takes the whole width or height, whichever is shorter.
		let one = TelemetryWidgetPage.bestFit(count: 1, in: CGSize(width: 360, height: 300), spacing: 8)
		#expect(one.columns == 1)
		#expect(one.side == 300)
		// A wide space with three readings puts them in a row.
		let wide = TelemetryWidgetPage.bestFit(count: 3, in: CGSize(width: 600, height: 180), spacing: 8)
		#expect(wide.columns == 3)
	}

	@Test func aReadingTurnsOldAtTwoHours() {
		let reading = TelemetrySnapshot(time: now, temperature: 20)
		#expect(!reading.isStale(at: now.addingTimeInterval(2 * 3600 - 1)))
		#expect(reading.isStale(at: now.addingTimeInterval(2 * 3600)))
	}

	@Test func pagesHoldFourAndWrap() {
		let metrics = Array(TelemetryMetric.allCases.prefix(6))
		#expect(TelemetryWidgetPage.pageCount(for: 6) == 2)
		#expect(TelemetryWidgetPage.pageCount(for: 4) == 1)
		#expect(TelemetryWidgetPage.pageCount(for: 0) == 1)
		#expect(TelemetryWidgetPage.metrics(metrics, page: 0) == Array(metrics.prefix(4)))
		// A short last page.
		#expect(TelemetryWidgetPage.metrics(metrics, page: 1) == Array(metrics.suffix(2)))
		#expect(TelemetryWidgetPage.next(after: 0, pageCount: 2) == 1)
		#expect(TelemetryWidgetPage.next(after: 1, pageCount: 2) == 0)
		#expect(TelemetryWidgetPage.next(after: 0, pageCount: 1) == 0)
	}
}
