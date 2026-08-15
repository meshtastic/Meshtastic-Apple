//
//  AccessoryError.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  tvOS-local shim for the small subset of `AccessoryError` that the reused
//  `TCPConnection.swift` references (`.disconnected`, `.eventStreamCancelled`).
//
//  On iOS these live inside `AccessoryManager.swift`, which is tangled with
//  CoreBluetooth / CoreLocation / ActivityKit and is deliberately NOT linked into
//  the tvOS target. Because the reused `TCPConnection.swift` is compiled into the
//  tvOS app module, its `AccessoryError` references resolve to this definition.
//

import Foundation

enum AccessoryError: Error, LocalizedError {
	case disconnected(String)
	case eventStreamCancelled
	case connectionFailed(String)

	var errorDescription: String? {
		switch self {
		case .disconnected(let message):
			return message
		case .eventStreamCancelled:
			return "Event stream was cancelled"
		case .connectionFailed(let message):
			return message
		}
	}
}
