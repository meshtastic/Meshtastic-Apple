//
//  URLHandler.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 6/27/25.
//
import SwiftUI
import SwiftData
import OSLog
import TipKit
import MeshtasticProtobufs

struct ContactURLHandler {

	static var minimumContactVersion = "2.6.9"

	/// The shared-contact link prefix — the contact counterpart to
	/// `MeshtasticChannelURL.canonicalPrefix`.
	static let urlPrefix = "meshtastic.org/v/#"

	/// True when this URL is a Meshtastic shared-contact link. Single source of
	/// truth for every contact-link entry point (universal links, custom scheme,
	/// QR scans, and NFC tags).
	static func canHandle(_ url: URL) -> Bool {
		url.absoluteString.lowercased().contains(urlPrefix)
	}

	@MainActor
	static func handleContactUrl(url: URL, accessoryManager: AccessoryManager) {
		let supportedVersion = accessoryManager.checkIsVersionSupported(forVersion: minimumContactVersion)

		if !supportedVersion {
			let alertController = UIAlertController(
				title: "Firmware Upgrade Required",
				message: "In order to import contacts via a QR code you need firmware version 2.6.9 or greater.",
				preferredStyle: .alert
			)
			alertController.addAction(UIAlertAction(
				title: "Close",
				style: .cancel,
				handler: nil
			))
			if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
			   let rootViewController = windowScene.windows.first?.rootViewController {
				rootViewController.present(alertController, animated: true)
			}
			Logger.services.debug("User Alerted that a firmware upgrade is required to import contacts.")
		} else {
			let components = url.absoluteString.components(separatedBy: "#")
			if let contactData = components.last {
				let decodedString = contactData.base64urlToBase64()
				if let decodedData = Data(base64Encoded: decodedString) {
					do {
						let contact = try MeshtasticProtobufs.SharedContact(serializedBytes: decodedData)
						// Present the SwiftUI confirmation sheet (AddContactConfirmationView)
						// via published state, mirroring the channel-link import flow.
						accessoryManager.appState?.pendingContactToAdd = PendingContact(
							contact: contact,
							base64UrlString: contactData
						)
						Logger.services.debug("Contact data extracted from URL: \(contactData, privacy: .public)")
					} catch {
						Logger.services.error("Failed to parse contact data: \(error.localizedDescription, privacy: .public)")
						if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
						   let rootViewController = windowScene.windows.first?.rootViewController {
							let errorAlert = UIAlertController(
								title: "Error",
								message: "Could not process contact information. Invalid format.",
								preferredStyle: .alert
							)
							errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
							rootViewController.present(errorAlert, animated: true)
						}
					}
				}
			}
		}
	}
}
