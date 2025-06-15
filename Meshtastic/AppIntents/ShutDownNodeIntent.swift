//
//  ShutDownNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/24/24.
//

import Foundation
import AppIntents

struct ShutDownNodeIntent: AppIntent {
	static var title: LocalizedStringResource = "Shut Down"

	static var description: IntentDescription = "Send a shutdown to the node you are connected to"

	func perform() async throws -> some IntentResult {
		try await requestConfirmation(result: .result(dialog: "Shut Down Node?"))

		if !BLEManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		// Safely unwrap the connectedNode using if let
		if let connectedPeripheralNum = BLEManager.shared.connectedPeripheral?.num,
		   let connectedNode = getNodeInfo(id: connectedPeripheralNum, context: PersistenceController.shared.container.viewContext),
		   let fromUser = connectedNode.user,
		   let toUser = connectedNode.user {

			// Attempt to send shutdown, throw an error if it fails
			if !BLEManager.shared.sendShutdown(fromUser: fromUser, toUser: toUser) {
				throw AppIntentErrors.AppIntentError.message("Failed to shut down")
			}
		} else {
			throw AppIntentErrors.AppIntentError.message("Failed to retrieve connected node or required data")
		}
		return .result()
	}
}
