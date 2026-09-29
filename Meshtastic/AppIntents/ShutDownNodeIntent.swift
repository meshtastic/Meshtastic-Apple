//
//  ShutDownNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/24/24.
//

import Foundation
import AppIntents

struct ShutDownNodeIntent: AppIntent {
	static let title: LocalizedStringResource = "Shut Down"

	static let description: IntentDescription = "Send a shutdown to the node you are connected to"

	@Parameter(title: "Radio", description: "The connected radio to use. Leave empty for the radio chosen for CarPlay & Siri, or the only one connected.")
	var radio: RadioEntity?

	func perform() async throws -> some IntentResult {
		try await requestConfirmation(result: .result(dialog: "Shut Down Node?"))

		// The radio it names, the CarPlay & Siri radio, or the only one connected (T320).
		let radioNum = try await AccessoryManager.shared.intentRadio(radio?.nodeNum).radioNum(
			noRadio: AppIntentErrors.AppIntentError.notConnected,
			needsValue: $radio.needsValueError("Which radio?")
		)

		// Safely unwrap the connectedNode using if let
		let context = await MainActor.run { PersistenceController.shared.context }
		if let connectedNode = getNodeInfo(id: radioNum, context: context),
		   let fromUser = connectedNode.user,
		   let toUser = connectedNode.user {

			// Attempt to send shutdown, throw an error if it fails
			do {
				try await AccessoryManager.shared.sendShutdown(fromUser: fromUser, toUser: toUser)
			} catch {
				throw AppIntentErrors.AppIntentError.message("Failed to shut down")
			}
		} else {
			throw AppIntentErrors.AppIntentError.message("Failed to retrieve connected node or required data")
		}
		return .result()
	}
}
