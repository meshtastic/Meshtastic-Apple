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
		for dm in telemetry where dm.metricsType == 0 {
				csvString += "\n"
				csvString += String(dm.batteryLevel)
				csvString += ", "
				csvString += String(dm.voltage)
				csvString += ", "
				csvString += String(dm.channelUtilization)
				csvString += ", "
				csvString += String(dm.airUtilTx)
				csvString += ", "
				csvString += String(dm.uptimeSeconds)
				csvString += ", "
				csvString += dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
		}
	} else if metricsType == 1 {
		// Create Environment Telemetry Header
		csvString = "Temperature, Relative Humidity, Barometric Pressure, Indoor Air Quality, Gas Resistance, \("timestamp".localized)"
		for dm in telemetry where dm.metricsType == 1 {
			csvString += "\n"
			csvString += String(dm.temperature.localeTemperature())
			csvString += ", "
			csvString += String(dm.relativeHumidity)
			csvString += ", "
			csvString += String(dm.barometricPressure)
			csvString += ", "
			csvString += String(dm.iaq)
			csvString += ", "
			csvString += String(dm.gasResistance)
			csvString += ", "
			csvString += dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
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
	for d in detections {
		csvString += "\n"
		csvString += d.messagePayload ?? "Detection"
		csvString += ", "
		csvString += d.timestamp.formattedDate(format: dateFormatString).localized
	}
	return csvString
}

func logToCsvFile(log: [OSLogEntryLog]) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
	// Create PAX Header
	csvString = "Process, Category, Level, Message, \("timestamp".localized)"
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
		csvString += l.date.formattedDate(format: dateFormatString)
	}
	return csvString
}

func paxToCsvFile(pax: [PaxCounterEntity]) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
	// Create PAX Header
	csvString = "BLE, WiFi, Total Pax, Uptime, \("timestamp".localized)"
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
		csvString += p.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
	}
	return csvString
}

func positionToCsvFile(positions: [PositionEntity]) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
	// Create Position Header
	csvString = "SeqNo, Latitude, Longitude, Altitude, Sats, Speed, Heading, SNR, \("timestamp".localized)"
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
		csvString += pos.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
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
