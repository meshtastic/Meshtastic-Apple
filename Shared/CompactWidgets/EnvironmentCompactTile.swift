//
//  EnvironmentCompactTile.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//

import SwiftUI

/// The Environment widget's tile for one reading: the same compact tile node
/// details shows for it, given the same values, for environment, air quality
/// and power readings alike. Readings without a node
/// details tile use `ReadingCompactWidget`, and a reading the node no longer
/// sends shows a dash.
struct EnvironmentCompactTile: View {
	let metric: EnvironmentMetric
	let environment: EnvironmentSnapshot

	var body: some View {
		if let reading = metric.reading(in: environment) {
			tile(reading)
		} else {
			ReadingCompactWidget(systemImage: metric.systemImage, title: metric.title(in: environment), value: Constants.nilValueIndicator)
		}
	}

	@ViewBuilder
	private func tile(_ reading: EnvironmentReading) -> some View {
		switch metric {
		case .temperature:
			// As node details: the short temperature and the TEMP label.
			WeatherConditionsCompactWidget(temperature: environment.temperature?.shortFormattedTemperature() ?? reading.value, symbolName: "cloud.sun", description: "TEMP")
		case .relativeHumidity:
			if let humidity = environment.relativeHumidity, let percent = Int(exactly: humidity.rounded()) {
				HumidityCompactWidget(humidity: percent, dewPoint: dewPoint)
			} else {
				generic(reading)
			}
		case .barometricPressure:
			PressureCompactWidget(pressure: reading.value, unit: "hPa", low: (environment.barometricPressure ?? 0) <= 1009.144)
		case .wind:
			WindCompactWidget(speed: windText(environment.windSpeed) ?? reading.value, gust: (environment.windGust ?? 0) > 0 ? windText(environment.windGust) : "", direction: reading.detail)
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
			ParticulateMatterCompactWidget(label: "PM1.0", value: environment.pm10Standard ?? 0)
		case .pm25:
			ParticulateMatterCompactWidget(label: "PM2.5", value: environment.pm25Standard ?? 0)
		case .pm100:
			ParticulateMatterCompactWidget(label: "PM10", value: environment.pm100Standard ?? 0)
		case .co2:
			Co2CompactWidget(ppm: environment.co2 ?? 0)
		case .dewPoint, .gasResistance, .iaq, .lux:
			generic(reading)
		default:
			if let channel = metric.powerChannel,
			   let value = (channel.isVoltage ? environment.powerVoltages : environment.powerCurrents)?[channel.index] {
				PowerMetricCompactWidget(type: channel.isVoltage ? .voltage : .current, value: value, title: metric.title(in: environment))
			} else {
				generic(reading)
			}
		}
	}

	private func generic(_ reading: EnvironmentReading) -> some View {
		ReadingCompactWidget(systemImage: metric.systemImage, title: metric.title(in: environment), value: reading.value, unit: reading.unit, detail: reading.detail, valueColor: reading.color)
	}

	/// The humidity tile's dew point line, formatted as node details does.
	private var dewPoint: String? {
		guard let temperature = environment.temperature, let humidity = environment.relativeHumidity, humidity > 0 else { return nil }
		return calculateDewPoint(temp: temperature, relativeHumidity: humidity).formatted(.number.precision(.fractionLength(0))) + "°"
	}

	/// Wind as node details formats it: whole, in the locale's speed unit.
	private func windText(_ metersPerSecond: Float?) -> String? {
		guard let metersPerSecond, metersPerSecond.isFinite else { return nil }
		return Measurement(value: Double(metersPerSecond), unit: UnitSpeed.metersPerSecond)
			.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
	}
}
