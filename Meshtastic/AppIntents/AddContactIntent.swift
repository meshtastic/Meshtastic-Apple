//
//  AddContactIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 5/13/25.
//

import AppIntents
import MeshtasticProtobufs

struct AddContactIntent: AppIntent {
	static var title: LocalizedStringResource = "Import Contact"
	static var description: IntentDescription = "Takes a Meshtastic contact URL and saves it to the nodes database"

	@Parameter(title: "Contact URL", description: "The URL for the node to import")
	var contactUrl: URL

	// Define the function that performs the main logic
	func perform() async throws -> some IntentResult {
		// Ensure the BLE Manager is connected
		if !BLEManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		if contactUrl.absoluteString.lowercased().contains("meshtastic.org/v/#") {
			
			let components = self.contactUrl.absoluteString.components(separatedBy: "#")
			// Extract contact information from the URL
			if let contactData = components.last {
				
				let decodedString = contactData.base64urlToBase64()
				if let decodedData = Data(base64Encoded: decodedString) {
					do {
						let success = BLEManager.shared.addContactFromURL(base64UrlString: contactData)
						if !success {
							throw AppIntentErrors.AppIntentError.message("Failed to import contact")
						}

					} catch {
						throw AppIntentErrors.AppIntentError.message("Failed to parse contact data: \(error.localizedDescription)")
						
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
