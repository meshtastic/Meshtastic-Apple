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
		if !(await AccessoryManager.shared.isConnected) {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		if !(await AccessoryManager.shared.isConnected) {
			try await AccessoryManager.shared.disconnect()
		} else {
			throw AppIntentErrors.AppIntentError.message("Error disconnecting node")
		}

	return .result()
	}
}
