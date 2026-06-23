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
