//
//  WidgetEnvironmentTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
import Foundation
import Testing
@testable import Meshtastic

/// The Environment widget (design#179): which nodes and metrics it offers, how a
/// reading reads, when it's old, and how the large size pages.
@Suite("Widget environment")
struct WidgetEnvironmentTests {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	private func snapshot(nodes: [NodeSnapshot], radio: Int64? = 1) -> WidgetSnapshot {
		WidgetSnapshot(
			generatedAt: now, connectionState: .connected, radioNodeNum: radio,
			radioLongName: nil, radioShortName: nil, radioBatteryLevel: nil, localStats: nil,
			nodes: nodes, totalNodeCount: nodes.count, unreadChannelMessages: 0,
			unreadDirectMessages: 0, recentMessages: []
		)
	}

	private func node(_ num: Int64, environment: EnvironmentSnapshot? = nil) -> NodeSnapshot {
		var node = NodeSnapshot(
			num: num, longName: "Node \(num)", shortName: "N\(num)", colorSeed: UInt32(num),
			batteryLevel: nil, snr: nil, rssi: nil, signalRating: nil,
			lastHeard: now, isOnline: true, hopsAway: 0,
			latitude: nil, longitude: nil, isFavorite: false
		)
		node.environment = environment
		return node
	}

	@Test func snapshotsFromBeforeEnvironmentStillDecode() throws {
		let encoded = try JSONEncoder().encode(snapshot(nodes: [node(2)]))
		var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
		var nodes = try #require(object["nodes"] as? [[String: Any]])
		nodes[0].removeValue(forKey: "environment")
		object["nodes"] = nodes
		let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
		#expect(decoded.nodes.first?.environment == nil)
	}

	@Test func offersOnlyNodesWithReadingsConnectedRadioFirst() {
		let reading = EnvironmentSnapshot(time: now, temperature: 20)
		let nodes = EnvironmentNodeQuery.environmentNodes(in: snapshot(nodes: [
			node(3, environment: reading),
			node(2),
			node(1, environment: reading)
		]))
		#expect(nodes.map(\.num) == [1, 3])
	}

	@Test func defaultsToTheFirstFourInTheDesignOrder() {
		let reading = EnvironmentSnapshot(time: now, temperature: 20, relativeHumidity: 50, barometricPressure: 1013, lux: 300, soilMoisture: 40)
		#expect(EnvironmentMetric.defaults(for: reading) == [.temperature, .relativeHumidity, .barometricPressure, .dewPoint])
		#expect(EnvironmentMetric.defaults(for: nil).isEmpty)
	}

	@Test func offersOnlyMetricsTheNodeReported() {
		let reading = EnvironmentSnapshot(time: now, relativeHumidity: 50, windSpeed: 3)
		// No dew point without a temperature.
		#expect(reading.reportedMetrics == [.relativeHumidity, .wind])
	}

	@Test func aMissingReadingIsNilAndAZeroIsZero() {
		let reading = EnvironmentSnapshot(time: now, lux: 0, soilMoisture: 0)
		#expect(EnvironmentMetric.lux.reading(in: reading)?.value == "0")
		#expect(EnvironmentMetric.soilMoisture.reading(in: reading)?.value == "0")
		#expect(EnvironmentMetric.radiation.reading(in: reading) == nil)
	}

	@Test func temperatureAndPressureAreWholePressureInHectopascals() {
		let reading = EnvironmentSnapshot(time: now, temperature: 21.6, barometricPressure: 1013.7)
		let pressure = EnvironmentMetric.barometricPressure.reading(in: reading)
		#expect(pressure?.value == "1014")
		#expect(pressure?.unit == "hPa")
		let temperature = EnvironmentMetric.temperature.reading(in: reading)
		// Whichever unit the locale uses, the value matches the app's conversion, whole.
		let expected = Float(21.6).localeTemperature().formatted(.number.precision(.fractionLength(0)))
		#expect(temperature?.value == expected)
		#expect(temperature?.unit == "°C" || temperature?.unit == "°F")
	}

	@Test func aNonFiniteReadingIsNoReading() {
		let reading = EnvironmentSnapshot(time: now, temperature: .nan)
		#expect(EnvironmentMetric.temperature.reading(in: reading) == nil)
		#expect(reading.reportedMetrics.isEmpty)
	}

	@Test func iaqCarriesItsBand() {
		let reading = EnvironmentSnapshot(time: now, iaq: 120)
		let iaq = EnvironmentMetric.iaq.reading(in: reading)
		#expect(iaq?.value == "120")
		#expect(iaq?.detail == Iaq.lightlyPolluted.description)
		#expect(iaq?.color == Iaq.lightlyPolluted.color)
	}

	@Test func aReadingTurnsOldAtTwoHours() {
		let reading = EnvironmentSnapshot(time: now, temperature: 20)
		#expect(!reading.isStale(at: now.addingTimeInterval(2 * 3600 - 1)))
		#expect(reading.isStale(at: now.addingTimeInterval(2 * 3600)))
	}

	@Test func pagesHoldFourAndWrap() {
		let metrics = Array(EnvironmentMetric.allCases.prefix(6))
		#expect(EnvironmentWidgetPage.pageCount(for: 6) == 2)
		#expect(EnvironmentWidgetPage.pageCount(for: 4) == 1)
		#expect(EnvironmentWidgetPage.pageCount(for: 0) == 1)
		#expect(EnvironmentWidgetPage.metrics(metrics, page: 0) == Array(metrics.prefix(4)))
		// A short last page.
		#expect(EnvironmentWidgetPage.metrics(metrics, page: 1) == Array(metrics.suffix(2)))
		#expect(EnvironmentWidgetPage.next(after: 0, pageCount: 2) == 1)
		#expect(EnvironmentWidgetPage.next(after: 1, pageCount: 2) == 0)
		#expect(EnvironmentWidgetPage.next(after: 0, pageCount: 1) == 0)
	}
}
