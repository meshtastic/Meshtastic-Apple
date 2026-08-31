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
		guard await PersistenceBootstrap.shared.waitUntilReady() else {
			throw AppIntentErrors.AppIntentError.message("Local data is unavailable")
		}
		// Ensure the BLE Manager is connected
		if !(await AccessoryManager.shared.isConnected) {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		let channelLink: MeshtasticChannelURL
		do {
			channelLink = try MeshtasticChannelURL.parse(channelUrl.absoluteString)
		} catch let error as MeshtasticChannelURL.ParseError {
			throw AppIntentErrors.AppIntentError.message(error.localizedDescription)
		}
		// Require explicit confirmation before mutating radio state, mirroring the in-app
		// QR/URL flow (SaveChannelQRCode) and the destructive intents (ShutDownNodeIntent /
		// FactoryResetNodeIntent). Without this, an untrusted Shortcut could silently replace
		// the radio's channel list, PSKs, and LoRa config in the background.
		// requestConfirmation throws if the user declines; let that cancellation propagate
		// unchanged rather than mislabeling it as a save failure.
		// The add path only sends channels; the replace path also rewrites LoRa config and
		// reboots the radio. Describe each case accurately so the prompt matches the mutation.
		// Annotate the type so the ternary's branches coerce to IntentDialog (a bare ternary
		// of String literals would otherwise infer String, which IntentDialog can't accept).
		let dialog: IntentDialog = channelLink.addChannels
			? "This will add channels to your connected Meshtastic radio. Your LoRa settings will not change. Continue?"
			: "This will REPLACE the channels and LoRa settings on your connected Meshtastic radio. Continue?"
		try await requestConfirmation(result: .result(dialog: dialog))
		do {
			try await AccessoryManager.shared.saveChannelSet(
				channelSet: channelLink.channelSet,
				addChannels: channelLink.addChannels
			)
		} catch {
			throw AppIntentErrors.AppIntentError.message("Failed to save the channel settings.")
		}
		return .result()
	}
}
