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
		let isConnected = await AccessoryManager.shared.isConnected
		if !isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		do {
			try await AccessoryManager.shared.disconnect()
		} catch {
			throw AppIntentErrors.AppIntentError.message("Error disconnecting node")
		}

	return .result()
	}
}
