//
//  FactoryResetNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/25/24.
//

import Foundation
import AppIntents

struct FactoryResetNodeIntent: AppIntent {
	static let title: LocalizedStringResource = "Factory Reset"
	static let description: IntentDescription = "Perform a factory reset on the node you are connected to"
	@Parameter(title: "Hard Reset", description: "In addition to Config, Keys and BLE bonds will be wiped", default: false)
	var hardReset: Bool
	@Parameter(title: "Provide Confirmation", description: "Show a confirmation dialog before performing the factory reset", default: true)
	var provideConfirmation: Bool

	@Parameter(title: "Radio", description: "The connected radio to use. Leave empty for the radio chosen for CarPlay & Siri, or the only one connected.")
	var radio: RadioEntity?

	func perform() async throws -> some IntentResult {
		// Request user confirmation before performing the factory reset
		if provideConfirmation {
			try await requestConfirmation(result: .result(dialog: "Are you sure you want to factory reset the node?"), confirmationActionName: ConfirmationActionName
				.custom(acceptLabel: "Factory Reset", acceptAlternatives: [], denyLabel: "Cancel", denyAlternatives: [], destructive: true))
		}

		// The radio it names, the CarPlay & Siri radio, or the only one connected (T320).
		let radioNum = try await AccessoryManager.shared.intentRadio(radio?.nodeNum).radioNum(
			noRadio: AppIntentErrors.AppIntentError.notConnected,
			needsValue: $radio.needsValueError("Which radio?")
		)

		// Safely unwrap the connected node information
		let context = await MainActor.run { PersistenceController.shared.context }
		if let connectedNode = getNodeInfo(id: radioNum, context: context),
		   let fromUser = connectedNode.user,
		   let toUser = connectedNode.user {

			// Attempt to send a factory reset command, throw an error if it fails
			do {
				try await AccessoryManager.shared.sendFactoryReset(fromUser: fromUser, toUser: toUser, resetDevice: hardReset)
			} catch {
				throw AppIntentErrors.AppIntentError.message("Failed to perform factory reset")
			}
		} else {
			throw AppIntentErrors.AppIntentError.message("Failed to retrieve connected node or required data")
		}
//		
		return .result()
	}
}
