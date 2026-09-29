//
//  MessageNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 11/9/24.
//

import Foundation
import AppIntents

struct MessageNodeIntent: AppIntent {
	static var title: LocalizedStringResource = "Send a Direct Message"

	static var description: IntentDescription = "Send a message to a certain meshtastic node"

	@Parameter(title: "Message")
	var messageContent: String

	@Parameter(title: "Node Number")
	var nodeNumber: Int

	@Parameter(title: "Radio", description: "The connected radio to use. Leave empty for the radio chosen for CarPlay & Siri, or the only one connected.")
	var radio: RadioEntity?

	static var parameterSummary: some ParameterSummary {
		Summary("Send \(\.$messageContent) to \(\.$nodeNumber)")
	}
	func perform() async throws -> some IntentResult {

		// Convert messageContent to data and check its length
		guard let messageData = messageContent.data(using: .utf8) else {
			throw AppIntentErrors.AppIntentError.message("Failed to encode message content")
		}

		if messageData.count > 200 {
			throw $messageContent.needsValueError("Message content exceeds 200 bytes.")
		}

		// The radio it names, the CarPlay & Siri radio, or the only one connected (T320).
		let viaRadio = try await AccessoryManager.shared.intentRadio(radio?.nodeNum).radioNum(
			noRadio: AppIntentErrors.AppIntentError.notConnected,
			needsValue: $radio.needsValueError("Which radio?")
		)

		do {
			try await AccessoryManager.shared.sendMessage(message: messageContent, toUserNum: Int64(nodeNumber), channel: 0, isEmoji: false, replyID: 0, viaRadio: viaRadio)
		} catch {
			throw AppIntentErrors.AppIntentError.message("Failed to send message")
		}

	return .result()
	}
}
