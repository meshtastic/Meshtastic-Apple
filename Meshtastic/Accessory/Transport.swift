//
//  Transport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import CommonCrypto

enum TransportType: String, CaseIterable {
	case ble = "BLE"
	case tcp = "TCP"
	case serial = "Serial"
}

enum TransportStatus: Equatable {
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

typealias TransportRSSIUpdate = (deviceId: UUID, rssi: Int)

protocol WirelessTransport: Transport {
	func rssiStream() async -> AsyncStream<TransportRSSIUpdate>
}

// Used to make stable-ish ID's for accessories that don't have a UUID
extension String {
	func toUUIDFormatHash() -> UUID? {
		// Convert string to data
		guard let data = self.data(using: .utf8) else { return nil }

		// Create buffer for SHA-256 hash (32 bytes)
		var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

		// Perform SHA-256 hashing
		_ = data.withUnsafeBytes { buffer in
			CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
		}

		// Take first 16 bytes (128 bits) for UUID
		let uuidBytes = Array(digest.prefix(16))

		// Create UUID from bytes
		return UUID(uuid: (
			uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
			uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
			uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
			uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
		))
	}
}
