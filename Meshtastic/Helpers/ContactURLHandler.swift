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
	static let canonicalPrefix = MeshContactURL.canonicalPrefix + "#"

	/// True when this URL is a Meshtastic shared-contact link. Single source of
	/// truth for every contact-link entry point (universal links, custom scheme,
	/// QR scans, and NFC tags).
	///
	/// Validates the host, path, and fragment rather than substring-matching the
	/// whole URL string, so a foreign link that merely embeds `meshtastic.org/v/#`
	/// (in a query or path) is not mistaken for a contact import.
	static func canHandle(_ url: URL) -> Bool {
		MeshContactURL.canHandle(url)
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
			do {
				let parsed = try MeshContactURL.parse(url.absoluteString)
				guard let appState = accessoryManager.appState else {
					Logger.services.error("Cannot present contact import: app state is not wired yet.")
					return
				}
				appState.pendingContactToAdd = PendingContact(
					contact: parsed.contact,
					base64UrlString: parsed.payload,
					exchangeRequested: parsed.exchangeRequested
				)
				Logger.services.debug("Validated a shared Meshtastic contact URL.")
			} catch {
				Logger.services.error("Failed to parse contact data: \(error.localizedDescription, privacy: .public)")
				presentInvalidContactAlert()
			}
		}
	}

	@MainActor
	private static func presentInvalidContactAlert() {
		guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
			  let rootViewController = windowScene.windows.first?.rootViewController else {
			return
		}
		let errorAlert = UIAlertController(
			title: "Error",
			message: "Could not process contact information. Invalid format.",
			preferredStyle: .alert
		)
		errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
		rootViewController.present(errorAlert, animated: true)
	}
}
