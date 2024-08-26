//
//  RestartNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/24/24.
//

import Foundation
import AppIntents

struct RestartNodeIntent: AppIntent {
	static var title: LocalizedStringResource = "Restart Node"

	static var description: IntentDescription = "Restart to the node you are connected to"
	

	func perform() async throws -> some IntentResult {
		
		try await requestConfirmation(result: .result(dialog: "Reboot Node?"))

		if !BLEManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}
		// Safely unwrap the connectedNode using if let
		if let connectedPeripheralNum = BLEManager.shared.connectedPeripheral?.num,
		   let connectedNode = getNodeInfo(id: connectedPeripheralNum, context: PersistenceController.shared.container.viewContext),
		   let fromUser = connectedNode.user,
		   let toUser = connectedNode.user,
		   let adminIndex = connectedNode.myInfo?.adminIndex {
		   
			// Attempt to send shutdown, throw an error if it fails
			if !BLEManager.shared.sendReboot(fromUser: fromUser, toUser: toUser, adminIndex: adminIndex) {
				throw AppIntentErrors.AppIntentError.message("Failed to restart")
			}
		} else {
			throw AppIntentErrors.AppIntentError.message("Failed to retrieve connected node or required data")
		}
		
		return .result()
	}
}

