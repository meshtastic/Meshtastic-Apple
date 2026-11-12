//
//  TelemetrySnapshot.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
//  A node's newest environment, air quality and power telemetry for the
//  Telemetry widget, and the metrics it can show (meshtastic/design#179). Readings stay in the units the
//  radio sends; the widget formats them the way node details does, so the
//  same reading reads the same in both places.
//

import Foundation
import SwiftUI

/// A node's newest environment, air quality and power telemetry rows. Nil
/// fields were not in the reading; a reported zero stays zero.
struct TelemetrySnapshot: Codable, Equatable {
	/// When the newest of the three rows arrived.
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
	/// Meters per second.
	var windGust: Float?
	/// Millimeters in the last hour.
	var rainfall1H: Float?
	var soilTemperature: Float?
	var soilMoisture: UInt32?
	/// µR/hr.
	var radiation: Float?
	/// Kilograms.
	var weight: Float?
	/// Air quality: PM1.0, PM2.5 and PM10 in µg/m³, and CO2 in ppm.
	var pm10Standard: UInt32?
	var pm25Standard: UInt32?
	var pm100Standard: UInt32?
	var co2: UInt32?
	/// Power channels 1 to 8: volts and milliamps, nil where not reported.
	var powerVoltages: [Float?]?
	var powerCurrents: [Float?]?
	/// The channels' names as node details shows them: the node's labels, or Channel N.
	var powerChannelNames: [String]?

	/// Design#166: a reading over two hours old is never shown as current.
	func isStale(at date: Date) -> Bool {
		date.timeIntervalSince(time) >= 2 * 3600
	}

	/// The metrics this reading has, in the widget's order.
	var reportedMetrics: [TelemetryMetric] {
		TelemetryMetric.allCases.filter { $0.reading(in: self) != nil }
	}
}

/// A metric the Telemetry widget can show, in the order design#179 lists
/// them. The order is also the default: until someone picks, the widget shows
/// the first ones the node reports.
enum TelemetryMetric: String, CaseIterable, Codable, Identifiable {
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
	case pm10
	case pm25
	case pm100
	case co2
	case power1Voltage, power1Current, power2Voltage, power2Current
	case power3Voltage, power3Current, power4Voltage, power4Current
	case power5Voltage, power5Current, power6Voltage, power6Current
	case power7Voltage, power7Current, power8Voltage, power8Current

	/// The power channel, counting from zero, and whether this is its voltage.
	var powerChannel: (index: Int, isVoltage: Bool)? {
		guard rawValue.hasPrefix("power"), let digit = rawValue.dropFirst(5).first?.wholeNumberValue else { return nil }
		return (digit - 1, rawValue.hasSuffix("Voltage"))
	}


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
		case .pm10: "PM1.0"
		case .pm25: "PM2.5"
		case .pm100: "PM10"
		case .co2: "CO2"
		default:
			// Power, before the node's channel names are known.
			if let channel = powerChannel {
				channel.isVoltage ? "Channel \(channel.index + 1) Voltage" : "Channel \(channel.index + 1) Current"
			} else {
				"\(rawValue)"
			}
		}
	}

	/// The title a tile shows: power channels by the node's labels, as node details names them.
	func title(in telemetry: TelemetrySnapshot?) -> String {
		guard let channel = powerChannel, let names = telemetry?.powerChannelNames, channel.index < names.count else {
			return String(localized: title)
		}
		let name = names[channel.index]
		return channel.isVoltage
			? String(localized: "\(name) Voltage", comment: "Power tile title. %@ is the channel's label, such as Solar or Channel 1.")
			: String(localized: "\(name) Current", comment: "Power tile title. %@ is the channel's label, such as Solar or Channel 1.")
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
		case .pm10, .pm25, .pm100: "aqi.medium"
		case .co2: "carbon.dioxide.cloud"
		default: powerChannel?.isVoltage == true ? "powerplug.fill" : "bolt.fill"
		}
	}

	/// The readings a widget shows: every one the node reports, in this order, less the hidden ones.
	static func shown(in telemetry: TelemetrySnapshot?, hiding hidden: [TelemetryMetric]) -> [TelemetryMetric] {
		(telemetry?.reportedMetrics ?? []).filter { !hidden.contains($0) }
	}

	/// The formatted reading, or nil when the reading doesn't have it. The
	/// units and precision match the tiles on node details:
	/// temperature and pressure whole, pressure always in hPa, the rest in the
	/// locale's units (design#53, design#99).
	func reading(in telemetry: TelemetrySnapshot) -> TelemetryReading? {
		switch self {
		case .temperature:
			return telemetry.temperature.flatMap(Self.temperature)
		case .relativeHumidity:
			return telemetry.relativeHumidity.flatMap { Self.whole($0, unit: "%") }
		case .barometricPressure:
			return telemetry.barometricPressure.flatMap { Self.whole($0, unit: "hPa") }
		case .dewPoint:
			guard let temperature = telemetry.temperature, let humidity = telemetry.relativeHumidity, humidity > 0 else { return nil }
			let dewPoint = Float(calculateDewPoint(temp: temperature, relativeHumidity: humidity, convertToLocale: false))
			return Self.temperature(dewPoint)
		case .gasResistance:
			return telemetry.gasResistance.flatMap { Self.decimal($0, digits: 1, unit: "MΩ") }
		case .iaq:
			guard let iaq = telemetry.iaq, iaq >= 0 else { return nil }
			let level = Iaq.getIaq(for: Int(iaq))
			return TelemetryReading(value: "\(iaq)", unit: nil, detail: level.description, color: level.color)
		case .lux:
			return telemetry.lux.flatMap { Self.whole($0, unit: "lx") }
		case .wind:
			guard let speed = telemetry.windSpeed, speed.isFinite else { return nil }
			let value = MetricsLocaleUnits.windSpeed(fromMetersPerSecond: speed)
			let direction = telemetry.windDirection.map { cardinalValue(from: Double($0)) }
			return TelemetryReading(
				value: value.formatted(.number.precision(.fractionLength(0))),
				unit: MetricsLocaleUnits.windSpeedLabel,
				detail: direction.flatMap { $0.isEmpty ? nil : $0 },
				color: nil
			)
		case .rain:
			guard let rain = telemetry.rainfall1H else { return nil }
			let digits = MetricsLocaleUnits.length == .millimeters ? 0 : 1
			return Self.decimal(MetricsLocaleUnits.length(fromMillimeters: rain), digits: digits, unit: MetricsLocaleUnits.lengthLabel)
		case .soilTemperature:
			return telemetry.soilTemperature.flatMap(Self.temperature)
		case .soilMoisture:
			return telemetry.soilMoisture.map { TelemetryReading(value: "\($0)", unit: "%", detail: nil, color: nil) }
		case .radiation:
			return telemetry.radiation.flatMap { Self.decimal($0, digits: 1, unit: "µR/hr") }
		case .weight:
			guard let weight = telemetry.weight else { return nil }
			return Self.decimal(MetricsLocaleUnits.mass(fromKilograms: weight), digits: 1, unit: MetricsLocaleUnits.massLabel)
		case .pm10:
			return telemetry.pm10Standard.map(Self.particulate)
		case .pm25:
			return telemetry.pm25Standard.map(Self.particulate)
		case .pm100:
			return telemetry.pm100Standard.map(Self.particulate)
		case .co2:
			guard let co2 = telemetry.co2 else { return nil }
			let level = Co2Level.level(for: co2)
			return TelemetryReading(value: co2.formatted(.number.grouping(.never)), unit: "ppm", detail: level.description, color: level.color)
		default:
			guard let channel = powerChannel else { return nil }
			let values = channel.isVoltage ? telemetry.powerVoltages : telemetry.powerCurrents
			guard let values, channel.index < values.count, let value = values[channel.index] else { return nil }
			// The power tile's precision: volts to two places, milliamps to one.
			return channel.isVoltage ? Self.decimal(value, digits: 2, unit: "V") : Self.decimal(value, digits: 1, unit: "mA")
		}
	}

	private static func particulate(_ value: UInt32) -> TelemetryReading {
		TelemetryReading(value: value.formatted(.number.grouping(.never)), unit: "µg/m³", detail: nil, color: nil)
	}

	private static func temperature(_ celsius: Float) -> TelemetryReading? {
		guard celsius.isFinite else { return nil }
		// The same locale setting localeTemperature() converts by.
		let fahrenheit = (NSLocale.current as NSLocale).object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey")) as? String == "Fahrenheit"
		return TelemetryReading(value: celsius.localeTemperature().formatted(.number.precision(.fractionLength(0))), unit: fahrenheit ? "°F" : "°C", detail: nil, color: nil)
	}

	private static func whole(_ value: Float, unit: String) -> TelemetryReading? {
		guard value.isFinite else { return nil }
		return TelemetryReading(value: value.formatted(.number.grouping(.never).precision(.fractionLength(0))), unit: unit, detail: nil, color: nil)
	}

	private static func decimal(_ value: Float, digits: Int, unit: String) -> TelemetryReading? {
		guard value.isFinite else { return nil }
		return TelemetryReading(value: value.formatted(.number.grouping(.never).precision(.fractionLength(digits))), unit: unit, detail: nil, color: nil)
	}
}

/// One metric's value as a tile shows it.
struct TelemetryReading: Equatable {
	let value: String
	let unit: String?
	/// A second line: the IAQ band or the wind's direction.
	let detail: String?
	/// The IAQ band's color.
	let color: Color?
}
