//
//  DisconnectNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 4/2/25.
//

#if canImport(AppIntents)
import Foundation
import AppIntents

@available(iOS 16.0, *)
struct DisconnectNodeIntent: AppIntent {
	static let title: LocalizedStringResource = "Disconnect Node"

	static let description: IntentDescription = "Disconnect the currently connected node"

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

#endif
