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
		
	} else if metricsType == 1 {
		
		// Create Environment Telemetry Header
		csvString = "Temperature, Relative Humidity, Barometric Pressure, Gas Resistance, Voltage, Current"
		
		for dm in telemetry{
			
			if dm.metricsType == 1 {
			
				csvString += "\n"
				csvString += String("\(dm.temperature)°")
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
				csvString += dm.time?.formattedDate(format: "yyyy-MM-dd HH:mm:ss") ?? "Unknown Age"
			}
		}
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
