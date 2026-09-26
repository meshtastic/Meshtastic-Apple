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

	@Parameter(title: "Radio Node Number", description: "The connected radio to send through, on its own channel with this number. Leave empty to use the radio chosen for CarPlay & Siri.")
	var radioNumber: Int?

	static var parameterSummary: some ParameterSummary {
		Summary("Send \(\.$messageContent) to \(\.$channelNumber)")
	}
	func perform() async throws -> some IntentResult {
		if !(await AccessoryManager.shared.isConnected) {
			throw AppIntentErrors.AppIntentError.notConnected
		}

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

		guard let viaRadio = await AccessoryManager.shared.intentRadioNum(radioNumber) else {
			throw $radioNumber.needsValueError("That radio isn't connected.")
		}

		do {
			try await AccessoryManager.shared.sendMessage(message: messageContent, toUserNum: 0, channel: Int32(channelNumber), isEmoji: false, replyID: 0, viaRadio: viaRadio)
		} catch {
			throw AppIntentErrors.AppIntentError.message("Failed to send message")
		}

	return .result()
	}
}
