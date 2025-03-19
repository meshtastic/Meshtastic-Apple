//
//  TelemetryEntity+CoreDataClass.swift
//
//
//  Created by Jake Bordens on 12/26/24.
//
//

import Foundation
import CoreData

// Manual implementation of the TelemetryEntry object for CoreData.
//   Add optional scalar types here using the @ManagedAttribute property wrapper.
//   CoreData is based on Objective-C, which doesn't have optional scalars.
//   The @ManagedAttribute property wrapper handles the conversion to optional scalars.

@objc(TelemetryEntity)
public class TelemetryEntity: NSManagedObject, Identifiable {

	@ManagedAttribute<Float>(attributeName: "airUtilTx") public var airUtilTx: Float?
	@ManagedAttribute<Float>(attributeName: "barometricPressure") public var barometricPressure: Float?
	@ManagedAttribute<Int32>(attributeName: "batteryLevel") public var batteryLevel: Int32?
	@ManagedAttribute<Float>(attributeName: "channelUtilization") public var channelUtilization: Float?
	@ManagedAttribute<Float>(attributeName: "current") public var current: Float?
	@ManagedAttribute<Float>(attributeName: "distance") public var distance: Float?
	@ManagedAttribute<Float>(attributeName: "gasResistance") public var gasResistance: Float?
	@ManagedAttribute<Int32>(attributeName: "iaq") public var iaq: Int32?
	@ManagedAttribute<Float>(attributeName: "powerCh1Current") var powerCh1Current: Float?
	@ManagedAttribute<Float>(attributeName: "powerCh1Voltage") var powerCh1Voltage: Float?
	@ManagedAttribute<Float>(attributeName: "powerCh2Current") var powerCh2Current: Float?
	@ManagedAttribute<Float>(attributeName: "powerCh2Voltage") var powerCh2Voltage: Float?
	@ManagedAttribute<Float>(attributeName: "powerCh3Current") var powerCh3Current: Float?
	@ManagedAttribute<Float>(attributeName: "powerCh3Voltage") var powerCh3Voltage: Float?
	@ManagedAttribute<Float>(attributeName: "relativeHumidity") public var relativeHumidity: Float?
	@ManagedAttribute<Int32>(attributeName: "rssi") public var rssi: Int32?
	@ManagedAttribute<Float>(attributeName: "snr") public var snr: Float?
	@ManagedAttribute<Float>(attributeName: "temperature") public var temperature: Float?
	@ManagedAttribute<Int32>(attributeName: "uptimeSeconds") public var uptimeSeconds: Int32?
	@ManagedAttribute<Float>(attributeName: "voltage") public var voltage: Float?
	@ManagedAttribute<Float>(attributeName: "weight") public var weight: Float?
	@ManagedAttribute<Int32>(attributeName: "windDirection") public var windDirection: Int32?
	@ManagedAttribute<Float>(attributeName: "windGust") public var windGust: Float?
	@ManagedAttribute<Float>(attributeName: "windLull") public var windLull: Float?
	@ManagedAttribute<Float>(attributeName: "windSpeed") public var windSpeed: Float?
	@ManagedAttribute<Float>(attributeName: "irLux") public var irLux: Float?
	@ManagedAttribute<Float>(attributeName: "lux") public var lux: Float?
	@ManagedAttribute<Float>(attributeName: "uvLux") public var uvLux: Float?
	@ManagedAttribute<Float>(attributeName: "whiteLux") public var whiteLux: Float?
	@ManagedAttribute<Float>(attributeName: "radiation") public var radiation: Float?
	@ManagedAttribute<Float>(attributeName: "rainfall1H") public var rainfall1H: Float?
	@ManagedAttribute<Float>(attributeName: "rainfall24H") public var rainfall24H: Float?
	@ManagedAttribute<Float>(attributeName: "soilTemperature") public var soilTemperature: Float?
	@ManagedAttribute<UInt32>(attributeName: "soilMoisture") public var soilMoisture: UInt32?

}
