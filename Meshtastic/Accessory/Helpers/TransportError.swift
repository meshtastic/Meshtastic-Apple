//
//  TransportErrors.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/30/25.
//

import CoreBluetooth

enum TransportError: LocalizedError {
	case bluetoothUnavailable
	case connectionFailed(reason: String)
	case coreBluetoothError(CBError)

	var errorDescription: String? {
		switch self {
		case .bluetoothUnavailable:
			return "Bluetooth is not available. Please enable it in your device's settings."
		case .connectionFailed(let reason):
			return "Could not connect to the device: \(reason)."
		case .coreBluetoothError(let cbError):
			// Map specific CBError values to a more user-friendly message
			switch cbError.code {
			case .connectionTimeout: // 6
				return "The node unexpectedly disconnected, it will automatically reconnect to the preferred radio when it comes back in range.".localized
			case .peripheralDisconnected: // 7
				return "The node is sleeping, disable power saving for a reliable connection to your phone.".localized
			case .peerRemovedPairingInformation: // 14
				return "The node has deleted its stored pairing information, but your device has not. To resolve this, you must forget the node under Settings > Bluetooth to clear the old, now invalid, pairing information.".localized
			default:
				// Fallback for other CBError codes
				return "A Bluetooth error occurred: \(cbError.localizedDescription)"
			}
		}
	}
}
