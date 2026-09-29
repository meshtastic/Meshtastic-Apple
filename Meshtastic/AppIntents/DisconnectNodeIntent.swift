//
//  DisconnectNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 4/2/25.
//

import Foundation
import AppIntents

struct DisconnectNodeIntent: AppIntent {
	static let title: LocalizedStringResource = "Disconnect Node"

	static let description: IntentDescription = "Disconnect the currently connected node"

	@Parameter(title: "Radio", description: "The connected radio to use. Leave empty for the radio chosen for CarPlay & Siri, or the only one connected.")
	var radio: RadioEntity?

	func perform() async throws -> some IntentResult {
		// The radio it names, the CarPlay & Siri radio, or the only one connected (T320).
		let radioNum = try await AccessoryManager.shared.intentRadio(radio?.nodeNum).radioNum(
			noRadio: AppIntentErrors.AppIntentError.notConnected,
			needsValue: $radio.needsValueError("Which radio?")
		)

		do {
			try await AccessoryManager.shared.disconnectRadio(nodeNum: radioNum)
		} catch {
			throw AppIntentErrors.AppIntentError.message("Error disconnecting node")
		}

	return .result()
	}
}
