//
//  EnvironmentSnapshot.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
//  A node's newest environment telemetry for the Environment widget, and the
//  metrics it can show (meshtastic/design#179). Readings stay in the units the
//  radio sends; the widget formats them the way node details does, so the
//  same reading reads the same in both places.
//

import Foundation
import SwiftUI

/// The newest environment telemetry row for a node. Nil fields were not in
/// the reading; a reported zero stays zero.
struct EnvironmentSnapshot: Codable, Equatable {
	let time: Date
	var temperature: Float?
	var relativeHumidity: Float?
	/// hPa.
	var barometricPressure: Float?
	/// MΩ.
	var gasResistance: Float?
	var iaq: Int32?
	var lux: Float?
	/// Meters per second.
	var windSpeed: Float?
	/// Degrees the wind comes from.
	var windDirection: Int32?
	/// Millimeters in the last hour.
	var rainfall1H: Float?
	var soilTemperature: Float?
	var soilMoisture: UInt32?
	/// µR/hr.
	var radiation: Float?
	/// Kilograms.
	var weight: Float?

	/// Design#166: a reading over two hours old is never shown as current.
	func isStale(at date: Date) -> Bool {
		date.timeIntervalSince(time) >= 2 * 3600
	}

	/// The metrics this reading has, in the widget's order.
	var reportedMetrics: [EnvironmentMetric] {
		EnvironmentMetric.allCases.filter { $0.reading(in: self) != nil }
	}
}

/// A metric the Environment widget can show, in the order design#179 lists
/// them. The order is also the default: until someone picks, the widget shows
/// the first ones the node reports.
enum EnvironmentMetric: String, CaseIterable, Codable, Identifiable {
	case temperature
	case relativeHumidity
	case barometricPressure
	case dewPoint
	case gasResistance
	case iaq
	case lux
	case wind
	case rain
	case soilTemperature
	case soilMoisture
	case radiation
	case weight

	/// How many metrics a widget can be set to.
	static let maximumCount = 8
	/// How many the widget shows before someone picks.
	static let defaultCount = 4

	var id: String { rawValue }

	var title: LocalizedStringResource {
		switch self {
		case .temperature: "Temperature"
		case .relativeHumidity: "Humidity"
		case .barometricPressure: "Pressure"
		case .dewPoint: "Dew Point"
		case .gasResistance: "Gas Resistance"
		case .iaq: "IAQ"
		case .lux: "Light"
		case .wind: "Wind"
		case .rain: "Rain"
		case .soilTemperature: "Soil Temperature"
		case .soilMoisture: "Soil Moisture"
		case .radiation: "Radiation"
		case .weight: "Weight"
		}
	}

	var systemImage: String {
		switch self {
		case .temperature: "thermometer.medium"
		case .relativeHumidity: "humidity"
		case .barometricPressure: "gauge"
		case .dewPoint: "drop"
		case .gasResistance: "aqi.medium"
		case .iaq: "aqi.low"
		case .lux: "sun.max"
		case .wind: "wind"
		case .rain: "cloud.rain"
		case .soilTemperature: "thermometer.variable.and.figure"
		case .soilMoisture: "drop.triangle"
		case .radiation: "atom"
		case .weight: "scalemass"
		}
	}

	/// The metrics to show before someone picks: the first ones the reading has.
	static func defaults(for environment: EnvironmentSnapshot?) -> [EnvironmentMetric] {
		Array((environment?.reportedMetrics ?? []).prefix(defaultCount))
	}

	/// The formatted reading, or nil when the reading doesn't have it. The
	/// units and precision match the environment tiles on node details:
	/// temperature and pressure whole, pressure always in hPa, the rest in the
	/// locale's units (design#53, design#99).
	func reading(in environment: EnvironmentSnapshot) -> EnvironmentReading? {
		switch self {
		case .temperature:
			return environment.temperature.flatMap(Self.temperature)
		case .relativeHumidity:
			return environment.relativeHumidity.flatMap { Self.whole($0, unit: "%") }
		case .barometricPressure:
			return environment.barometricPressure.flatMap { Self.whole($0, unit: "hPa") }
		case .dewPoint:
			guard let temperature = environment.temperature, let humidity = environment.relativeHumidity, humidity > 0 else { return nil }
			let dewPoint = Float(calculateDewPoint(temp: temperature, relativeHumidity: humidity, convertToLocale: false))
			return Self.temperature(dewPoint)
		case .gasResistance:
			return environment.gasResistance.flatMap { Self.decimal($0, digits: 1, unit: "MΩ") }
		case .iaq:
			guard let iaq = environment.iaq, iaq >= 0 else { return nil }
			let level = Iaq.getIaq(for: Int(iaq))
			return EnvironmentReading(value: "\(iaq)", unit: nil, detail: level.description, color: level.color)
		case .lux:
			return environment.lux.flatMap { Self.whole($0, unit: "lx") }
		case .wind:
			guard let speed = environment.windSpeed, speed.isFinite else { return nil }
			let value = MetricsLocaleUnits.windSpeed(fromMetersPerSecond: speed)
			let direction = environment.windDirection.map { cardinalValue(from: Double($0)) }
			return EnvironmentReading(
				value: value.formatted(.number.precision(.fractionLength(0))),
				unit: MetricsLocaleUnits.windSpeedLabel,
				detail: direction.flatMap { $0.isEmpty ? nil : $0 },
				color: nil
			)
		case .rain:
			guard let rain = environment.rainfall1H else { return nil }
			let digits = MetricsLocaleUnits.length == .millimeters ? 0 : 1
			return Self.decimal(MetricsLocaleUnits.length(fromMillimeters: rain), digits: digits, unit: MetricsLocaleUnits.lengthLabel)
		case .soilTemperature:
			return environment.soilTemperature.flatMap(Self.temperature)
		case .soilMoisture:
			return environment.soilMoisture.map { EnvironmentReading(value: "\($0)", unit: "%", detail: nil, color: nil) }
		case .radiation:
			return environment.radiation.flatMap { Self.decimal($0, digits: 1, unit: "µR/hr") }
		case .weight:
			guard let weight = environment.weight else { return nil }
			return Self.decimal(MetricsLocaleUnits.mass(fromKilograms: weight), digits: 1, unit: MetricsLocaleUnits.massLabel)
		}
	}

	private static func temperature(_ celsius: Float) -> EnvironmentReading? {
		guard celsius.isFinite else { return nil }
		// The same locale setting localeTemperature() converts by.
		let fahrenheit = (NSLocale.current as NSLocale).object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey")) as? String == "Fahrenheit"
		return EnvironmentReading(value: celsius.localeTemperature().formatted(.number.precision(.fractionLength(0))), unit: fahrenheit ? "°F" : "°C", detail: nil, color: nil)
	}

	private static func whole(_ value: Float, unit: String) -> EnvironmentReading? {
		guard value.isFinite else { return nil }
		return EnvironmentReading(value: value.formatted(.number.grouping(.never).precision(.fractionLength(0))), unit: unit, detail: nil, color: nil)
	}

	private static func decimal(_ value: Float, digits: Int, unit: String) -> EnvironmentReading? {
		guard value.isFinite else { return nil }
		return EnvironmentReading(value: value.formatted(.number.grouping(.never).precision(.fractionLength(digits))), unit: unit, detail: nil, color: nil)
	}
}

/// One metric's value as a tile shows it.
struct EnvironmentReading: Equatable {
	let value: String
	let unit: String?
	/// A second line: the IAQ band or the wind's direction.
	let detail: String?
	/// The IAQ band's color.
	let color: Color?
}
