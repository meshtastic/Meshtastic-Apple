//
//  AccessoryManager+LaunchFallback.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation

// MARK: - Connecting at launch (feature 021)

extension AccessoryManager {

	/// The first radio's connect is running or waiting for the handshake gate. `isConnecting` only says so
	/// once it has passed the gate (T152).
	var hasFirstConnectInProgress: Bool {
		connectAttempts.values.contains { $0.isFirst && !$0.isCancelled }
	}
}
