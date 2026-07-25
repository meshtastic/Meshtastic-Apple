//
//  SaveChannelSettingsIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 10/6/24.
//

import Foundation
import AppIntents

// Define the AppIntent for saving channel settings from a URL
struct SaveChannelSettingsIntent: AppIntent {
	// Define a title and description for the intent
	static let title: LocalizedStringResource = "Save Channel Settings"
	static let description: IntentDescription = "Takes a Meshtastic channel URL and saves the channel settings."

	// Define the input for the intent (the channel URL)
	@Parameter(title: "Channel URL", description: "The URL for the channel settings")
	var channelUrl: URL

	// Define the function that performs the main logic
	func perform() async throws -> some IntentResult {
		// Ensure the BLE Manager is connected
		if !(await AccessoryManager.shared.isConnected) {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		do {
			let channelLink = try MeshtasticChannelURL.parse(channelUrl.absoluteString)
			// Require explicit confirmation before mutating radio state, mirroring the in-app
			// QR/URL flow (SaveChannelQRCode) and the destructive intents (ShutDownNodeIntent /
			// FactoryResetNodeIntent). Without this, an untrusted Shortcut could silently replace
			// the radio's channel list, PSKs, and LoRa config in the background.
			let mode = channelLink.addChannels ? "add to" : "REPLACE"
			try await requestConfirmation(
				result: .result(dialog: "This will \(mode) the channels and LoRa settings on your connected Meshtastic radio. Continue?")
			)
			try await AccessoryManager.shared.saveChannelSet(
				channelSet: channelLink.channelSet,
				addChannels: channelLink.addChannels
			)
			return .result()
		} catch let error as MeshtasticChannelURL.ParseError {
			throw AppIntentErrors.AppIntentError.message(error.localizedDescription)
		} catch {
			throw AppIntentErrors.AppIntentError.message("Failed to save the channel settings.")
		}
	}
}
