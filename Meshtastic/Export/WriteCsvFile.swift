//
//  WriteCsvFile.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/15/22.
//

import SwiftUI
import OSLog

func telemetryToCsvFile(telemetry: [TelemetryEntity], metricsType: Int) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
	if metricsType == 0 {
		// Create Device Metrics Header
		csvString = "\("battery.level".localized), \("voltage".localized), \("channel.utilization".localized), \("airtime".localized), \("uptime".localized), \("timestamp".localized)"
		for telemetryEntity in telemetry where telemetryEntity.metricsType == 0 {
				csvString += "\n"
				csvString += String(telemetryEntity.batteryLevel)
				csvString += ", "
				csvString += String(telemetryEntity.voltage)
				csvString += ", "
				csvString += String(telemetryEntity.channelUtilization)
				csvString += ", "
				csvString += String(telemetryEntity.airUtilTx)
				csvString += ", "
				csvString += String(telemetryEntity.uptimeSeconds)
				csvString += ", "
				csvString += telemetryEntity.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
		}
	} else if metricsType == 1 {
		// Create Environment Telemetry Header
		csvString = "Temperature, Relative Humidity, Barometric Pressure, Indoor Air Quality, Gas Resistance, \("timestamp".localized)"
		for telemetryEntity in telemetry where telemetryEntity.metricsType == 1 {
			csvString += "\n"
			csvString += String(telemetryEntity.temperature.localeTemperature())
			csvString += ", "
			csvString += String(telemetryEntity.relativeHumidity)
			csvString += ", "
			csvString += String(telemetryEntity.barometricPressure)
			csvString += ", "
			csvString += String(telemetryEntity.iaq)
			csvString += ", "
			csvString += String(telemetryEntity.gasResistance)
			csvString += ", "
			csvString += telemetryEntity.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
		}
	} else if metricsType == 2 {
		// Create Power Metrics Header
		csvString = "Channel 1 Voltage, Channel 1 Current, Channel 2 Voltage, Channel 2 Current, Channel 3 Voltage, Channel 3 Current, \("timestamp".localized)"
		for telemetryEntity in telemetry where telemetryEntity.metricsType == 2 {
			csvString += "\n"
			csvString += String(telemetryEntity.powerCh1Voltage)
			csvString += ", "
			csvString += String(telemetryEntity.powerCh1Current)
			csvString += ", "
			csvString += String(telemetryEntity.powerCh2Voltage)
			csvString += ", "
			csvString += String(telemetryEntity.powerCh2Current)
			csvString += ", "
			csvString += String(telemetryEntity.powerCh3Voltage)
			csvString += ", "
			csvString += String(telemetryEntity.powerCh3Current)
			csvString += ", "
			csvString += telemetryEntity.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
		}
	}
	return csvString
}

func detectionsToCsv(detections: [MessageEntity]) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
	// Create Header
	csvString = "Detection event, \("timestamp".localized)"
	for direction in detections {
		csvString += "\n"
		csvString += direction.messagePayload ?? "Detection"
		csvString += ", "
		csvString += direction.timestamp.formattedDate(format: dateFormatString).localized
	}
	return csvString
}

func logToCsvFile(log: [OSLogEntryLog]) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
	// Create PAX Header
	csvString = "Process, Category, Level, Message, \("timestamp".localized)"
	for logEntry in log {
		csvString += "\n"
		csvString += String(logEntry.process)
		csvString += ", "
		csvString += String(logEntry.category)
		csvString += ", "
		csvString += String(logEntry.level.description)
		csvString += ", "
		csvString += String(logEntry.composedMessage)
		csvString += ", "
		csvString += logEntry.date.formattedDate(format: dateFormatString)
	}
	return csvString
}

func paxToCsvFile(pax: [PaxCounterEntity]) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
	// Create PAX Header
	csvString = "BLE, WiFi, Total Pax, Uptime, \("timestamp".localized)"
	for paxCounterEntity in pax {
		csvString += "\n"
		csvString += String(paxCounterEntity.ble)
		csvString += ", "
		csvString += String(paxCounterEntity.wifi)
		csvString += ", "
		csvString += String(paxCounterEntity.ble + paxCounterEntity.wifi)
		csvString += ", "
		csvString += String(paxCounterEntity.uptime)
		csvString += ", "
		csvString += paxCounterEntity.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
	}
	return csvString
}

func positionToCsvFile(positions: [PositionEntity]) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
	// Create Position Header
	csvString = "SeqNo, Latitude, Longitude, Altitude, Sats, Speed, Heading, SNR, \("timestamp".localized)"
	for position in positions {
		csvString += "\n"
		csvString += String(position.seqNo)
		csvString += ", "
		csvString += String((position.latitude ?? 0))
		csvString += ", "
		csvString += String(position.longitude ?? 0)
		csvString += ", "
		csvString += String(position.altitude)
		csvString += ", "
		csvString += String(position.satsInView)
		csvString += ", "
		csvString += String(position.speed)
		csvString += ", "
		csvString += String(position.heading)
		csvString += ", "
		csvString += String(position.snr)
		csvString += ", "
		csvString += position.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
	}
	return csvString
}

func routeToCsvFile(locations: [LocationEntity]) -> String {
	var csvString: String = ""
	// Create Position Header
	csvString = "Id, Latitude, Longitude, Altitude, Speed, Heading"
	for location in locations {
		csvString += "\n"
		csvString += String(location.id)
		csvString += ", "
		csvString += String((location.latitude ?? 0))
		csvString += ", "
		csvString += String(location.longitude ?? 0)
		csvString += ", "
		csvString += String(location.altitude)
		csvString += ", "
		csvString += String(location.speed)
		csvString += ", "
		csvString += String(location.heading)
	}
	return csvString
}
