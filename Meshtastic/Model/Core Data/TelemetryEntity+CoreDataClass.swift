//
//  TelemetryEntity+CoreDataClass.swift
//  
//
//  Created by Jake Bordens on 12/26/24.
//
//

import Foundation
import CoreData

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
	@ManagedAttribute<Float>(attributeName: "irLux") public var irLux: Float?
	@ManagedAttribute<Float>(attributeName: "lux") public var lux: Float?
	@ManagedAttribute<Float>(attributeName: "radiation") public var radiation: Float?
	@ManagedAttribute<Float>(attributeName: "relativeHumidity") public var relativeHumidity: Float?
	@ManagedAttribute<Int32>(attributeName: "rssi") public var rssi: Int32?
	@ManagedAttribute<Float>(attributeName: "snr") public var snr: Float?
	@ManagedAttribute<Float>(attributeName: "temperature") public var temperature: Float?
	@ManagedAttribute<Int32>(attributeName: "uptimeSeconds") public var uptimeSeconds: Int32?
	@ManagedAttribute<Float>(attributeName: "uvLux") public var uvLux: Float?
	@ManagedAttribute<Float>(attributeName: "voltage") public var voltage: Float?
	@ManagedAttribute<Float>(attributeName: "weight") public var weight: Float?
	@ManagedAttribute<Float>(attributeName: "whiteLux") public var whiteLux: Float?
	@ManagedAttribute<Int32>(attributeName: "windDirection") public var windDirection: Int32?
	@ManagedAttribute<Float>(attributeName: "windGust") public var windGust: Float?
	@ManagedAttribute<Float>(attributeName: "windLull") public var windLull: Float?
	@ManagedAttribute<Float>(attributeName: "windSpeed") public var windSpeed: Float?
	
}
