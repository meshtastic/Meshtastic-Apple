//
//  Transport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation

enum TransportType: String, CaseIterable {
	case ble = "BLE"
	case tcp = "TCP"
	case serial = "Serial"
}

enum TransportStatus {
	case uninitialized
	case ready
	case discovering
	case error(String)
}

protocol Transport {
	var type: TransportType { get }
	var status: TransportStatus { get }

	// Discovers devices asynchronously. For ongoing scans (e.g., BLE), this can yield via AsyncStream.
	func discoverDevices() -> AsyncStream<Device>

	// Connects to a device and returns a Connection.
	func connect(to device: Device) async throws -> any Connection
}

protocol WirelessTransport: Transport {
	var rssiDelegate: RSSIDelegate? { get set }
}
