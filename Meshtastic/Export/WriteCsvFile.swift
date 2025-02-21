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
		csvString = "\("battery.level".localized), \("Voltage".localized), \("channel.utilization".localized), \("airtime".localized), \("uptime".localized), \("Timestamp".localized)"
		for dm in telemetry where dm.metricsType == 0 {
			csvString += "\n"
			csvString += dm.batteryLevel?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.voltage?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.channelUtilization?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.airUtilTx?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.uptimeSeconds?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
		}
	} else if metricsType == 1 {
		// Create Environment Telemetry Header
		csvString = "Temperature, Relative Humidity, Barometric Pressure, Indoor Air Quality, Gas Resistance, \("Timestamp".localized)"
		for dm in telemetry where dm.metricsType == 1 {
			csvString += "\n"
			csvString += dm.temperature?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.relativeHumidity?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.barometricPressure?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.iaq?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.gasResistance?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
		}
	} else if metricsType == 2 {
		// Create Power Metrics Header
		csvString = "Channel 1 Voltage, Channel 1 Current, Channel 2 Voltage, Channel 2 Current, Channel 3 Voltage, Channel 3 Current, \("Timestamp".localized)"
		for dm in telemetry where dm.metricsType == 2 {
			csvString += "\n"
			csvString += dm.powerCh1Voltage?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.powerCh1Current?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.powerCh2Voltage?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.powerCh2Current?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.powerCh3Voltage?.formatted(.number.grouping(.never)) ?? ""
			csvString += ", "
			csvString += dm.powerCh3Current?.formatted(.number.grouping(.never)) ?? ""
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
	csvString = "Detection event, \("Timestamp".localized)"
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
		csvString += l.date.formattedDate(format: dateFormatString)
	}
	return csvString
}

func paxToCsvFile(pax: [PaxCounterEntity]) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
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
		csvString += p.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
	}
	return csvString
}

func positionToCsvFile(positions: [PositionEntity]) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
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
