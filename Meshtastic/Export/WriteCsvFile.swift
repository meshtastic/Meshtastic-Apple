//
//  WriteCsvFile.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/15/22.
//

import SwiftUI

func telemetryToCsvFile(telemetry: [TelemetryEntity], metricsType: Int) -> String {
	var csvString: String = ""
	let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
	let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
	if metricsType == 0 {
		// Create Device Metrics Header
		csvString = "\("battery.level".localized), \("voltage".localized), \("channel.utilization".localized), \("airtime".localized), \("timestamp".localized)"
		for dm in telemetry {
			if dm.metricsType == 0 {
				csvString += "\n"
				csvString += String(dm.batteryLevel)
				csvString += ", "
				csvString += String(dm.voltage)
				csvString += ", "
				csvString += String(dm.channelUtilization)
				csvString += ", "
				csvString += String(dm.airUtilTx)
				csvString += ", "
				csvString += dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
			}
		}
	} else if metricsType == 1 {
		// Create Environment Telemetry Header
		csvString = "Temperature, Relative Humidity, Barometric Pressure, Gas Resistance, \("voltage".localized), \("current".localized), \("timestamp".localized)"
		for dm in telemetry {
			if dm.metricsType == 1 {
				csvString += "\n"
				csvString += String(dm.temperature.localeTemperature())
				csvString += ", "
				csvString += String(dm.relativeHumidity)
				csvString += ", "
				csvString += String(dm.barometricPressure)
				csvString += ", "
				csvString += String(dm.gasResistance)
				csvString += ", "
				csvString += String(dm.voltage)
				csvString += ", "
				csvString += String(dm.current)
				csvString += ", "
				csvString += dm.time?.formattedDate(format: dateFormatString) ?? "unknown.age".localized
			}
		}
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
