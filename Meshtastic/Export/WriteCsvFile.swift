//
//  WriteCsvFile.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/15/22.
//

import SwiftUI
import OSLog

/// A number for a CSV field, in a fixed locale so a decimal comma can't split the field; blank
/// when there's no reading.
private func csvNumber<T: BinaryFloatingPoint>(_ value: T?) -> String {
	guard let value else { return "" }
	return value.formatted(FloatingPointFormatStyle<T>(locale: Locale(identifier: "en_US_POSIX")).grouping(.never))
}

private func csvNumber<T: BinaryInteger>(_ value: T?) -> String {
	guard let value else { return "" }
	return value.formatted(IntegerFormatStyle<T>(locale: Locale(identifier: "en_US_POSIX")).grouping(.never))
}

func telemetryToCsvFile<S: Sequence>(telemetry: S, metricsType: Int) -> String where S.Element == TelemetryEntity {
	var csvString: String = ""
	if metricsType == 0 {
		// Create Device Metrics Header
		csvString = "\("battery.level".localized), \("Voltage".localized), \("Channel Utilization".localized), \("airtime".localized), \("Uptime".localized), \("Timestamp".localized)"
		for dm in telemetry where dm.metricsType == 0 {
			csvString += "\n"
			csvString += csvNumber(dm.batteryLevel)
			csvString += ", "
			csvString += csvNumber(dm.voltage)
			csvString += ", "
			csvString += csvNumber(dm.channelUtilization)
			csvString += ", "
			csvString += csvNumber(dm.airUtilTx)
			csvString += ", "
			csvString += csvNumber(dm.uptimeSeconds)
			csvString += ", "
			csvString += dm.time?.formatted(date: .numeric, time: .shortened).replacing(",", with: "") ?? ""
		}
	} else if metricsType == 1 {
		// Create Environment Telemetry Header
		csvString = "Temperature, Relative Humidity, Barometric Pressure, Indoor Air Quality, Gas Resistance, \("Timestamp".localized)"
		for dm in telemetry where dm.metricsType == 1 {
			csvString += "\n"
			csvString += csvNumber(dm.temperature)
			csvString += ", "
			csvString += csvNumber(dm.relativeHumidity)
			csvString += ", "
			csvString += csvNumber(dm.barometricPressure)
			csvString += ", "
			csvString += csvNumber(dm.iaq)
			csvString += ", "
			csvString += csvNumber(dm.gasResistance)
			csvString += ", "
			csvString += dm.time?.formatted(date: .numeric, time: .shortened).replacing(",", with: "") ?? ""
		}
	} else if metricsType == 2 {
		// Create Power Metrics Header, one voltage and current pair per channel
		csvString = (1...TelemetryEntity.powerChannelCount)
			.map { "Channel \($0) Voltage, Channel \($0) Current" }
			.joined(separator: ", ") + ", \("Timestamp".localized)"
		for dm in telemetry where dm.metricsType == 2 {
			csvString += "\n"
			for index in 0..<TelemetryEntity.powerChannelCount {
				csvString += csvNumber(dm.powerVoltage(channel: index))
				csvString += ", "
				csvString += csvNumber(dm.powerCurrent(channel: index))
				csvString += ", "
			}
			csvString += dm.time?.formatted(date: .numeric, time: .shortened).replacing(",", with: "") ?? ""
		}
	} else if metricsType == 3 {
		// Create Air Quality Metrics Header (particulate matter, µg/m³)
		csvString = "PM1.0 Std, PM2.5 Std, PM10 Std, PM1.0 Env, PM2.5 Env, PM10 Env, CO2, \("Timestamp".localized)"
		for dm in telemetry where dm.metricsType == 3 {
			csvString += "\n"
			csvString += csvNumber(dm.pm10Standard)
			csvString += ", "
			csvString += csvNumber(dm.pm25Standard)
			csvString += ", "
			csvString += csvNumber(dm.pm100Standard)
			csvString += ", "
			csvString += csvNumber(dm.pm10Environmental)
			csvString += ", "
			csvString += csvNumber(dm.pm25Environmental)
			csvString += ", "
			csvString += csvNumber(dm.pm100Environmental)
			csvString += ", "
			csvString += csvNumber(dm.co2)
			csvString += ", "
			csvString += dm.time?.formatted(date: .numeric, time: .shortened).replacing(",", with: "") ?? ""
		}
	} else if metricsType == 4 {
		// Create Local Stats Header
		csvString = "Noise Floor, Uptime, Relayed, Canceled, Dupes, Packets Tx, Packets Rx, Bad Rx, Nodes Online, Total Nodes, \("Timestamp".localized)"
		for dm in telemetry where dm.metricsType == 4 {
			csvString += "\n"
			csvString += csvNumber(dm.noiseFloor)
			csvString += ", "
			csvString += csvNumber(dm.uptimeSeconds)
			csvString += ", "
			csvString += csvNumber(dm.numTxRelay)
			csvString += ", "
			csvString += csvNumber(dm.numTxRelayCanceled)
			csvString += ", "
			csvString += csvNumber(dm.numRxDupe)
			csvString += ", "
			csvString += csvNumber(dm.numPacketsTx)
			csvString += ", "
			csvString += csvNumber(dm.numPacketsRx)
			csvString += ", "
			csvString += csvNumber(dm.numPacketsRxBad)
			csvString += ", "
			csvString += csvNumber(dm.numOnlineNodes)
			csvString += ", "
			csvString += csvNumber(dm.numTotalNodes)
			csvString += ", "
			csvString += dm.time?.formatted(date: .numeric, time: .shortened).replacing(",", with: "") ?? ""
		}
	}
	return csvString
}

func detectionsToCsv(detections: [MessageEntity]) -> String {
	var csvString: String = ""
	// Create Header
	csvString = "Detection event, \("Timestamp".localized)"
	for d in detections {
		csvString += "\n"
		csvString += d.messagePayload ?? "Detection"
		csvString += ", "
		csvString += d.timestamp.formatted(date: .numeric, time: .shortened).replacing(",", with: "")
	}
	return csvString
}

func logToCsvFile(log: [OSLogEntryLog]) -> String {
	var csvString: String = ""
	// Create PAX Header
	csvString = "Process, Category, Level, Message, \("Timestamp".localized)"
	for l in log {
		csvString += "\n"
		csvString += String(l.process)
		csvString += ", "
		csvString += String(l.category)
		csvString += ", "
		csvString += String(l.level.description)
		csvString += ", "
		csvString += String(l.composedMessage)
		csvString += ", "
		csvString += l.date.formatted(date: .numeric, time: .shortened).replacing(",", with: "")
	}
	return csvString
}

func paxToCsvFile(pax: [PaxCounterEntity]) -> String {
	var csvString: String = ""
	// Create PAX Header
	csvString = "BLE, WiFi, Total Pax, Uptime, \("Timestamp".localized)"
	for p in pax {
		csvString += "\n"
		csvString += String(p.ble)
		csvString += ", "
		csvString += String(p.wifi)
		csvString += ", "
		csvString += String(p.ble + p.wifi)
		csvString += ", "
		csvString += String(p.uptime)
		csvString += ", "
		csvString += p.time?.formatted(date: .numeric, time: .shortened).replacing(",", with: "") ?? ""
	}
	return csvString
}

func positionToCsvFile(positions: [PositionEntity]) -> String {
	var csvString: String = ""
	// Create Position Header
	csvString = "SeqNo, Latitude, Longitude, Altitude, Sats, Speed, Heading, SNR, \("Timestamp".localized)"
	for pos in positions {
		csvString += "\n"
		csvString += String(pos.seqNo)
		csvString += ", "
		csvString += String((pos.latitude ?? 0))
		csvString += ", "
		csvString += String(pos.longitude ?? 0)
		csvString += ", "
		csvString += String(pos.altitude)
		csvString += ", "
		csvString += String(pos.satsInView)
		csvString += ", "
		csvString += String(pos.speed)
		csvString += ", "
		csvString += String(pos.heading)
		csvString += ", "
		csvString += String(pos.snr)
		csvString += ", "
		csvString += pos.time?.formatted(date: .numeric, time: .shortened).replacing(",", with: "") ?? ""
	}
	return csvString
}

func routeToCsvFile(locations: [LocationEntity]) -> String {
	var csvString: String = ""
	// Create Position Header
	csvString = "Id, Latitude, Longitude, Altitude, Speed, Heading"
	for loc in locations {
		csvString += "\n"
		csvString += String(loc.id)
		csvString += ", "
		csvString += String((loc.latitude ?? 0))
		csvString += ", "
		csvString += String(loc.longitude ?? 0)
		csvString += ", "
		csvString += String(loc.altitude)
		csvString += ", "
		csvString += String(loc.speed)
		csvString += ", "
		csvString += String(loc.heading)
	}
	return csvString
}
