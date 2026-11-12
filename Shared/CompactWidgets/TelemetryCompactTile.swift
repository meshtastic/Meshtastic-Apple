//
//  TelemetryCompactTile.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//

import SwiftUI

/// The Telemetry widget's tile for one reading: the same compact tile node
/// details shows for it, given the same values, for environment, air quality
/// and power readings alike. Readings without a node
/// details tile use `ReadingCompactWidget`, and a reading the node no longer
/// sends shows a dash.
struct TelemetryCompactTile: View {
	let metric: TelemetryMetric
	let telemetry: TelemetrySnapshot

	var body: some View {
		if let reading = metric.reading(in: telemetry) {
			tile(reading)
		} else {
			ReadingCompactWidget(systemImage: metric.systemImage, title: metric.title(in: telemetry), value: Constants.nilValueIndicator)
		}
	}

	@ViewBuilder
	private func tile(_ reading: TelemetryReading) -> some View {
		switch metric {
		case .temperature:
			// As node details: the short temperature and the TEMP label.
			WeatherConditionsCompactWidget(temperature: telemetry.temperature?.shortFormattedTemperature() ?? reading.value, symbolName: "cloud.sun", description: "TEMP")
		case .relativeHumidity:
			if let humidity = telemetry.relativeHumidity, let percent = Int(exactly: humidity.rounded()) {
				HumidityCompactWidget(humidity: percent, dewPoint: dewPoint)
			} else {
				generic(reading)
			}
		case .barometricPressure:
			PressureCompactWidget(pressure: reading.value, unit: "hPa", low: (telemetry.barometricPressure ?? 0) <= 1009.144)
		case .wind:
			WindCompactWidget(speed: windText(telemetry.windSpeed) ?? reading.value, gust: (telemetry.windGust ?? 0) > 0 ? windText(telemetry.windGust) : "", direction: reading.detail)
		case .rain:
			RainfallCompactWidget(timespan: .rainfall1H, rainfall: reading.value, unit: reading.unit ?? "")
		case .radiation:
			RadiationCompactWidget(radiation: reading.value, unit: reading.unit ?? "")
		case .weight:
			WeightCompactWidget(weight: reading.value, unit: reading.unit ?? "")
		case .soilTemperature:
			SoilTemperatureCompactWidget(temperature: reading.value, unit: reading.unit ?? "")
		case .soilMoisture:
			SoilMoistureCompactWidget(moisture: reading.value, unit: reading.unit ?? "")
		case .pm10:
			ParticulateMatterCompactWidget(label: "PM1.0", value: telemetry.pm10Standard ?? 0)
		case .pm25:
			ParticulateMatterCompactWidget(label: "PM2.5", value: telemetry.pm25Standard ?? 0)
		case .pm100:
			ParticulateMatterCompactWidget(label: "PM10", value: telemetry.pm100Standard ?? 0)
		case .co2:
			Co2CompactWidget(ppm: telemetry.co2 ?? 0)
		case .dewPoint, .gasResistance, .iaq, .lux:
			generic(reading)
		default:
			if let channel = metric.powerChannel,
			   let value = (channel.isVoltage ? telemetry.powerVoltages : telemetry.powerCurrents)?[channel.index] {
				PowerMetricCompactWidget(type: channel.isVoltage ? .voltage : .current, value: value, title: metric.title(in: telemetry))
			} else {
				generic(reading)
			}
		}
	}

	private func generic(_ reading: TelemetryReading) -> some View {
		ReadingCompactWidget(systemImage: metric.systemImage, title: metric.title(in: telemetry), value: reading.value, unit: reading.unit, detail: reading.detail, valueColor: reading.color)
	}

	/// The humidity tile's dew point line, formatted as node details does.
	private var dewPoint: String? {
		guard let temperature = telemetry.temperature, let humidity = telemetry.relativeHumidity, humidity > 0 else { return nil }
		return calculateDewPoint(temp: temperature, relativeHumidity: humidity).formatted(.number.precision(.fractionLength(0))) + "°"
	}

	/// Wind as node details formats it: whole, in the locale's speed unit.
	private func windText(_ metersPerSecond: Float?) -> String? {
		guard let metersPerSecond, metersPerSecond.isFinite else { return nil }
		return Measurement(value: Double(metersPerSecond), unit: UnitSpeed.metersPerSecond)
			.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
	}
}
