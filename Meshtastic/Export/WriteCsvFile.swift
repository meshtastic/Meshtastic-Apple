//
//  WriteCsvFile.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/15/22.
//

import SwiftUI


func TelemetryToCsvFile(telemetry: [TelemetryEntity], metricsType: Int) -> String {
	
	var csvString: String = ""

	if metricsType == 0 {
		
		// Create Device Metrics Header
		csvString = "Battery Level, Voltage, Channel Utilization, Airtime, Timestamp"

		for dm in telemetry{
			
			if dm.metricsType == 0 {
			
				csvString += "\n"
				csvString += String("\(dm.batteryLevel) %")
				csvString += ", "
				csvString += String(dm.voltage)
				csvString += ", "
				csvString += String(dm.channelUtilization)
				csvString += ", "
				csvString += String(dm.airUtilTx)
				csvString += ", "
				csvString += dm.time?.formattedDate(format: "yyyy-MM-dd HH:mm:ss") ?? "Unknown Age"
			}
		}
		
	} else {
		// Create Device Telemetry Header
		csvString = "Battery Level, Voltage, Channel Utilization, Airtime, Timestamp"
	}
	
	return csvString
}

func PositionToCsvFile(positions: [PositionEntity]) -> String {
	
	var csvString: String = ""

	// Create Position Header
	csvString = "Latitude, Longitude, Altitude, Timestamp"

	for pos in positions {
		
		csvString += "\n"
		csvString += String(pos.latitude ?? 0)
		csvString += ", "
		csvString += String(pos.longitude ?? 0)
		csvString += ", "
		csvString += String(pos.altitude)
		csvString += ", "
		csvString += pos.time?.formattedDate(format: "yyyy-MM-dd HH:mm:ss") ?? "Unknown Age"
	}
	
	return csvString
}
