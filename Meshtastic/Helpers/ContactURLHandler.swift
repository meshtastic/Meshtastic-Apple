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
	static let canonicalPrefix = "https://meshtastic.org/v/#"

	private static let host = MeshtasticChannelURL.host
	private static let contactPathSegment = "v"

	/// True when this URL is a Meshtastic shared-contact link. Single source of
	/// truth for every contact-link entry point (universal links, custom scheme,
	/// QR scans, and NFC tags).
	///
	/// Validates the host, path, and fragment rather than substring-matching the
	/// whole URL string, so a foreign link that merely embeds `meshtastic.org/v/#`
	/// (in a query or path) is not mistaken for a contact import.
	static func canHandle(_ url: URL) -> Bool {
		guard let fragment = url.fragment, !fragment.isEmpty else { return false }

		let pathSegments = url.pathComponents
			.filter { $0 != "/" }
			.map { $0.lowercased() }

		// Custom scheme: the segment lands in the host for `meshtastic://v#…`
		// and in the path for `meshtastic:///v#…`.
		if url.scheme?.lowercased() == MeshtasticChannelURL.appScheme {
			if url.host == nil {
				return pathSegments == [contactPathSegment]
			}
			return url.host?.lowercased() == contactPathSegment && pathSegments.isEmpty
		}

		guard let urlHost = url.host?.lowercased(), urlHost == host || urlHost == "www.\(host)" else {
			return false
		}
		return pathSegments == [contactPathSegment]
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
						guard let appState = accessoryManager.appState else {
							// Without app state there is no sheet to present, so fail loudly
							// rather than dropping the import with no user feedback.
							Logger.services.error("Cannot present contact import: app state is not wired yet.")
							return
						}
						appState.pendingContactToAdd = PendingContact(
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
