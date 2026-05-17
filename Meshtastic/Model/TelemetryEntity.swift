//
//  TelemetryEntity.swift
//  Meshtastic
//
//  SwiftData model for telemetry data.
//  Replaces the manual Core Data TelemetryEntity+CoreDataClass/Properties files.
//

import Foundation
import SwiftData

@Model
final class TelemetryEntity {
	// Non-optional scalars
	var metricsType: Int32 = 0
	var numOnlineNodes: Int32 = 0
	var numPacketsRx: Int32 = 0
	var numPacketsRxBad: Int32 = 0
	var numPacketsTx: Int32 = 0
	var numRxDupe: Int32 = 0
	var numTotalNodes: Int32 = 0
	var numTxRelay: Int32 = 0
	var numTxRelayCanceled: Int32 = 0
	var time: Date?

	// Optional scalars (previously used @ManagedAttribute wrapper)
	var airUtilTx: Float?
	var barometricPressure: Float?
	var batteryLevel: Int32?
	var channelUtilization: Float?
	var current: Float?
	var distance: Float?
	var gasResistance: Float?
	var iaq: Int32?
	var irLux: Float?
	var lux: Float?
	var powerCh1Current: Float?
	var powerCh1Voltage: Float?
	var powerCh2Current: Float?
	var powerCh2Voltage: Float?
	var powerCh3Current: Float?
	var powerCh3Voltage: Float?
	var radiation: Float?
	var rainfall1H: Float?
	var rainfall24H: Float?
	var relativeHumidity: Float?
	var rssi: Int32?
	var snr: Float?
	var soilMoisture: UInt32?
	var soilTemperature: Float?
	var temperature: Float?
	var uptimeSeconds: Int32?
	var uvLux: Float?
	var voltage: Float?
	var weight: Float?
	var whiteLux: Float?
	var windDirection: Int32?
	var windGust: Float?
	var windLull: Float?
	var windSpeed: Float?

	// Relationship
	var nodeTelemetry: NodeInfoEntity?

	// Computed property
	var dewPoint: Float? {
		guard let temp = self.temperature, let rh = self.relativeHumidity else {
			return nil
		}
		return Float(calculateDewPoint(temp: temp, relativeHumidity: rh, convertToLocale: false))
	}

	init() {}
}
