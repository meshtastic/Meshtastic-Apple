// Copyright (C) 2022 Garth Vander Houwen

import SwiftUI
import CoreData
import OSLog
import TipKit
import MeshtasticProtobufs

@main
struct MeshtasticAppleApp: App {

	@UIApplicationDelegateAdaptor(MeshtasticAppDelegate.self) private var appDelegate

	@ObservedObject	var appState: AppState

	private let persistenceController: PersistenceController

	@Environment(\.scenePhase) var scenePhase
	@State var saveChannels = false
	@State var incomingUrl: URL?
	@State var channelSettings: String?
	@State var addChannels = false
	public var minimumContactVersion = "2.6.9"

	init() {
		let persistenceController = PersistenceController.shared
		let appState = AppState(
			router: Router()
		)
		self._appState = ObservedObject(wrappedValue: appState)

		// Initialize the BLEManager singleton with the necessary dependencies
		BLEManager.setup(appState: appState, context: persistenceController.container.viewContext)
		self.persistenceController = persistenceController

		// Wire up router
		self.appDelegate.router = appState.router
		// Show Tips
		try? Tips.resetDatastore()
	}

    var body: some Scene {
        WindowGroup {
			ContentView(
				appState: appState,
				router: appState.router
			)
			.environment(\.managedObjectContext, persistenceController.container.viewContext)
			.environmentObject(appState)
			.environmentObject(BLEManager.shared)
			.sheet(isPresented: $saveChannels) {
				SaveChannelQRCode(channelSetLink: channelSettings ?? "Empty Channel URL", addChannels: addChannels, bleManager: BLEManager.shared)
					.presentationDetents([.large])
					.presentationDragIndicator(.visible)
			}
			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
				Logger.mesh.debug("URL received \(userActivity, privacy: .public)")
				self.incomingUrl = userActivity.webpageURL
				self.saveChannels = false
				if self.incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/v/#") == true {
					handleContactUrl(url: self.incomingUrl!)
				} else if self.incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/e/#") == true {
					if let components = self.incomingUrl?.absoluteString.components(separatedBy: "#") {
						self.addChannels = Bool(self.incomingUrl?["add"] ?? "false") ?? false
						if (self.incomingUrl?.absoluteString.lowercased().contains("?")) != nil {
							guard let cs = components.last!.components(separatedBy: "?").first else {
								return
							}
							self.channelSettings = cs
						} else {
							guard let cs = components.first else {
								return
							}
							self.channelSettings = cs
						}
						Logger.services.debug("Add Channel \(self.addChannels, privacy: .public)")
					}
					self.saveChannels = true
					Logger.mesh.debug("User wants to open a Channel Settings URL: \(self.incomingUrl?.absoluteString ?? "No QR Code Link")")
				}
				if self.saveChannels {
					Logger.mesh.debug("User wants to open Channel Settings URL: \(String(describing: self.incomingUrl!.relativeString), privacy: .public)")
				}
			}
			.onOpenURL(perform: { (url) in
				Logger.mesh.debug("Some sort of URL was received \(url, privacy: .public)")
				self.incomingUrl = url
				if url.absoluteString.lowercased().contains("meshtastic.org/v/#") {
					handleContactUrl(url: url)
				} else if url.absoluteString.lowercased().contains("meshtastic.org/e/#") {
					if let components = self.incomingUrl?.absoluteString.components(separatedBy: "#") {
						self.addChannels = Bool(self.incomingUrl?["add"] ?? "false") ?? false
						if self.incomingUrl?.absoluteString.lowercased().contains("?") != nil {
							guard let cs = components.last!.components(separatedBy: "?").first else {
								return
							}
							self.channelSettings = cs
						} else {
							guard let cs = components.first else {
								return
							}
							self.channelSettings = cs
						}
						Logger.services.debug("Add Channel \(self.addChannels, privacy: .public)")
					}
					self.saveChannels = true
					Logger.mesh.debug("User wants to open a Channel Settings URL: \(self.incomingUrl?.absoluteString ?? "No QR Code Link", privacy: .public)")
				} else if url.absoluteString.lowercased().contains("meshtastic:///") {
					appState.router.route(url: url)
				}
			})
			.task {
				try? Tips.configure(
					[
						// Reset which tips have been shown and what parameters have been tracked, useful during testing and for this sample project
						.datastoreLocation(.applicationDefault),
						// When should the tips be presented? If you use .immediate, they'll all be presented whenever a screen with a tip appears.
						// You can adjust this on per tip level as well
						.displayFrequency(.immediate)
					]
				)
            }
		}
		.onChange(of: scenePhase) { (_, newScenePhase) in
			switch newScenePhase {
			case .background:
				Logger.services.info("🎬 [App] Scene is in the background")
				do {

					try persistenceController.container.viewContext.save()
					Logger.services.info("💾 [App] Saved CoreData ViewContext when the app went to the background.")

				} catch {

					Logger.services.error("💥 [App] Failed to save viewContext when the app goes to the background.")
				}
			case .inactive:
				Logger.services.info("🎬 [App] Scene is inactive")
			case .active:
				Logger.services.info("🎬 [App] Scene is active")
			@unknown default:
				Logger.services.error("🍎 [App] Apple must have changed something")
			}
		}
	}

	func handleContactUrl(url: URL) {
		let supportedVersion = UserDefaults.firmwareVersion == "0.0.0" ||  self.minimumContactVersion.compare(UserDefaults.firmwareVersion, options: .numeric) == .orderedAscending || minimumContactVersion.compare(UserDefaults.firmwareVersion, options: .numeric) == .orderedSame
		if !supportedVersion {
			// Show an alert letting the user know they need to upgrade their firmware to use the contact import.
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
			// Present the alert
			if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
			   let rootViewController = windowScene.windows.first?.rootViewController {
				rootViewController.present(alertController, animated: true)
			}
			Logger.services.debug("User Alerted that a firmware upgrade is required to import contacts.")
		} else {
			let components = url.absoluteString.components(separatedBy: "#")
			// Extract contact information from the URL
			if let contactData = components.last {
				let decodedString = contactData.base64urlToBase64()
				if let decodedData = Data(base64Encoded: decodedString) {
					do {
						let contact = try MeshtasticProtobufs.SharedContact(serializedBytes: decodedData)
						// Show an alert to confirm adding the contact
						let alertController = UIAlertController(
							title: "Add Contact",
							message: "Would you like to add \(contact.user.longName) as a contact?",
							preferredStyle: .alert
						)
						alertController.addAction(UIAlertAction(
							title: "Yes",
							style: .default,
							handler: { _ in
								let success = BLEManager.shared.addContactFromURL(base64UrlString: contactData)
								Logger.services.debug("Contact added from URL: \(success ? "success" : "failed")")
							}
						))
						alertController.addAction(UIAlertAction(
							title: "No",
							style: .cancel,
							handler: nil
						))
						// Present the alert
						if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
						   let rootViewController = windowScene.windows.first?.rootViewController {
							rootViewController.present(alertController, animated: true)
						}
						Logger.services.debug("Contact data extracted from URL: \(contactData, privacy: .public)")
					} catch {
						Logger.services.error("Failed to parse contact data: \(error.localizedDescription, privacy: .public)")
						// Show error alert to user
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
