//
//  RestartNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/24/24.
//

import Foundation
import AppIntents

struct RestartNodeIntent: AppIntent {
	static let title: LocalizedStringResource = "Restart"

	static let description: IntentDescription = "Restart to the node you are connected to"

	@Parameter(title: "Radio", description: "The connected radio to use. Leave empty for the radio chosen for CarPlay & Siri, or the only one connected.")
	var radio: RadioEntity?

	func perform() async throws -> some IntentResult {

		// The radio it names, the CarPlay & Siri radio, or the only one connected (T320).
		let radioNum = try await AccessoryManager.shared.intentRadio(radio?.nodeNum).radioNum(
			noRadio: AppIntentErrors.AppIntentError.notConnected,
			notConnected: AppIntentErrors.AppIntentError.message("That radio isn't connected."),
			needsValue: $radio.needsValueError("Which radio?")
		)
		// Safely unwrap the connectedNode using if let
		let context = await MainActor.run { PersistenceController.shared.context }
		if let connectedNode = getNodeInfo(id: radioNum, context: context),
		   let fromUser = connectedNode.user,
		   let toUser = connectedNode.user {

			// Attempt to send shutdown, throw an error if it fails
			do {
				try await AccessoryManager.shared.sendReboot(fromUser: fromUser, toUser: toUser)
			} catch {
				throw AppIntentErrors.AppIntentError.message("Failed to restart")
			}
		} else {
			throw AppIntentErrors.AppIntentError.message("Failed to retrieve connected node or required data")
		}
		return .result()
	}
}
