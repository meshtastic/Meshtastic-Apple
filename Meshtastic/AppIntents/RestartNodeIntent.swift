//
//  RestartNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/24/24.
//

import Foundation
import AppIntents

struct RestartNodeIntent: AppIntent {
	static var title: LocalizedStringResource = "Restart"

	static var description: IntentDescription = "Restart to the node you are connected to"

	func perform() async throws -> some IntentResult {

		if !AccessoryManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}
		// Safely unwrap the connectedNode using if let
		if let connectedPeripheralNum = AccessoryManager.shared.activeDeviceNum,
		   let connectedNode = getNodeInfo(id: connectedPeripheralNum, context: PersistenceController.shared.container.viewContext),
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
