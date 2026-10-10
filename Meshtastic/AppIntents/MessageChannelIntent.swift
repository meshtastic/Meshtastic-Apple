//
//  MessageChannelIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/9/24.
//

import Foundation
import AppIntents

struct MessageChannelIntent: AppIntent {
	static let title: LocalizedStringResource = "Send a Group Message"

	static let description: IntentDescription = "Send a message to a certain meshtastic channel"

	@Parameter(title: "Message")
	var messageContent: String

	@Parameter(title: "Channel", controlStyle: .stepper, inclusiveRange: (lowerBound: 0, upperBound: 7))
	var channelNumber: Int

	@Parameter(title: "Radio", description: "The connected radio to use. Leave empty for the radio chosen for CarPlay & Siri, or the only one connected.")
	var radio: RadioEntity?

	static var parameterSummary: some ParameterSummary {
		Summary("Send \(\.$messageContent) to \(\.$channelNumber)")
	}
	func perform() async throws -> some IntentResult {

		// Check if channel number is between 1 and 7
		guard (0...7).contains(channelNumber) else {
			throw $channelNumber.needsValueError("Channel number must be between 0 and 7.")
		}

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
			notConnected: AppIntentErrors.AppIntentError.message("That radio isn't connected."),
			needsValue: $radio.needsValueError("Which radio?")
		)

		do {
			try await AccessoryManager.shared.sendMessage(message: messageContent, toUserNum: 0, channel: Int32(channelNumber), isEmoji: false, replyID: 0, viaRadio: viaRadio)
		} catch {
			throw AppIntentErrors.AppIntentError.message("Failed to send message")
		}

	return .result()
	}
}
