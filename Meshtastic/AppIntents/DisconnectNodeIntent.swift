//
//  DisconnectNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 4/2/25.
//

import Foundation
import AppIntents

struct DisconnectNodeIntent: AppIntent {
	static var title: LocalizedStringResource = "Disconnect Node"

	static var description: IntentDescription = "Disconnect the currently connected node"

	func perform() async throws -> some IntentResult {
		if !BLEManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		if let connectedPeripheral = BLEManager.shared.connectedPeripheral,
				   connectedPeripheral.peripheral.state == .connected {
					BLEManager.shared.disconnectPeripheral(reconnect: false)
		} else {
			throw AppIntentErrors.AppIntentError.message("Error disconnecting node")
		}

	return .result()
	}
}
