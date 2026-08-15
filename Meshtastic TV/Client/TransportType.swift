//
//  TransportType.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Minimal local copy of the transport discriminator used by the reused
//  `Connection` / `TCPConnection` types. The iOS `Transport.swift` also defines
//  this enum, but that file drags in `Device` (and its BLE-only
//  `BLESignalStrength`), which the TCP-only tvOS target neither needs nor can link.
//

import Foundation

enum TransportType: String, CaseIterable, Codable {
	case ble = "BLE"
	case tcp = "TCP"
	case serial = "Serial"
}
