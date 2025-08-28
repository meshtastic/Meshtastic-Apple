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

		// Ensure the URL contains the expected "meshtastic.org/e/#" structure
		if channelUrl.absoluteString.lowercased().contains("meshtastic.org/e/#") {
			// Split the URL to get the portion after "#"
			let components = channelUrl.absoluteString.components(separatedBy: "#")
			// Add channels flag based on the URL query parameter (if present)
			let addChannels = Bool(channelUrl["add"] ?? "false") ?? false
			var channelSettings: String?
			// Extract the Base64 encoded channel settings (after "#")
			if let lastComponent = components.last {
				channelSettings = lastComponent.components(separatedBy: "?").first // Ignore any query parameters
			}

			// If valid channel settings are extracted, attempt to save them
			if let channelSettings = channelSettings {
				Task {
					do {
						// Call the AcessoryManager to save the channel settings
						try await AccessoryManager.shared.saveChannelSet(base64UrlString: channelSettings, addChannels: addChannels)
					} catch {
						throw AppIntentErrors.AppIntentError.message("Failed to save the channel settings.")
					}
				}
			} else {
				throw AppIntentErrors.AppIntentError.message("Invalid Channel URL: Unable to extract settings.")
			}

			// Return a success result
			return .result()
		} else {
			throw AppIntentErrors.AppIntentError.message("The URL is not a valid Meshtastic channel link.")
		}
	}
}
