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
				csvString += dm.batteryLevel.map { String($0) } ?? ""
				csvString += ", "
				csvString += dm.voltage.map { String($0) } ?? ""
				csvString += ", "
				csvString += dm.channelUtilization.map { String($0) } ?? ""
				csvString += ", "
				csvString += dm.airUtilTx.map { String($0) } ?? ""
				csvString += ", "
				csvString += dm.uptimeSeconds.map { String($0) } ?? ""
				csvString += ", "
				csvString += dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
		}
	} else if metricsType == 1 {
		// Create Environment Telemetry Header
		csvString = "Temperature, Relative Humidity, Barometric Pressure, Indoor Air Quality, Gas Resistance, Wind Direction, Wind Speed, Distance, Lux, White Lux, UV Lux, IR Lux, Radiation, \("timestamp".localized)"
		for dm in telemetry where dm.metricsType == 1 {
			csvString += "\n"
			csvString += dm.temperature.map { String($0.localeTemperature()) } ?? ""
			csvString += ", "
			csvString += dm.relativeHumidity.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.barometricPressure.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.iaq.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.gasResistance.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.windDirection.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.windSpeed.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.distance.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.lux.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.whiteLux.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.uvLux.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.irLux.map { String($0) } ?? ""
			csvString += ", "
			csvString += dm.radiation.map { String($0) } ?? ""
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
