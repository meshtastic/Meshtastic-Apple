//
//  Device.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation

struct Device: Identifiable, Hashable {
	let id: UUID
	var name: String
	var transportType: TransportType
	var identifier: String // e.g., UUID for BLE, IP:port for TCP, port path for Serial

	var num: Int64?
	var shortName: String?
	var longName: String?
	var firmwareVersion: String?
	var hardwareModel: String?
	var rssi: Int?
	var lastUpdate: Date?

	var connectionState: ConnectionState
	var wasRestored: Bool = false
	init(id: UUID, name: String, transportType: TransportType, identifier: String, connectionState: ConnectionState = .disconnected, rssi: Int? = nil, num: Int64? = nil, wasRestored: Bool = false) {
		self.id = id
		self.name = name
		self.transportType = transportType
		self.identifier = identifier
		self.connectionState = connectionState
		self.rssi = rssi
		self.num = num
		self.wasRestored = wasRestored
	}

	var rssiString: String {
		if let rssi {
			return "\(rssi) dBm"
		} else {
			return "n/a"
		}
	}

	func getSignalStrength() -> BLESignalStrength? {
		guard let rssi else { return nil }
		if NSNumber(value: rssi).compare(NSNumber(-65)) == ComparisonResult.orderedDescending {
			return BLESignalStrength.strong
		} else if NSNumber(value: rssi).compare(NSNumber(-85)) == ComparisonResult.orderedDescending {
			return BLESignalStrength.normal
		} else {
			return BLESignalStrength.weak
		}
	}

}
