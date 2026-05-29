//
//  AddContactIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 5/13/25.
//

import AppIntents
import MeshtasticProtobufs

struct AddContactIntent: AppIntent {
	static let title: LocalizedStringResource = "Add Contact"
	static let description: IntentDescription = "Takes a Meshtastic contact URL and saves it to the nodes database"

	@Parameter(title: "Contact URL", description: "The URL for the node to add")
	var contactUrl: URL

	// Define the function that performs the main logic
	func perform() async throws -> some IntentResult {
		// Ensure the BLE Manager is connected
		if !(await AccessoryManager.shared.isConnected) {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		if contactUrl.absoluteString.lowercased().contains("meshtastic.org/v/#") {
			let components = self.contactUrl.absoluteString.components(separatedBy: "#")
			// Extract contact information from the URL
			if let contactData = components.last {
				let decodedString = contactData.base64urlToBase64()
				if Data(base64Encoded: decodedString) != nil {
					do {
						try await AccessoryManager.shared.addContactFromURL(base64UrlString: contactData)
					} catch {
						throw AppIntentErrors.AppIntentError.message("Failed to add/parse contact data: \(error.localizedDescription)")
					}
				}
			}
			// Return a success result
			return .result()
		} else {
			throw AppIntentErrors.AppIntentError.message("The URL is not a valid Meshtastic contact link")
		}
	}
}
