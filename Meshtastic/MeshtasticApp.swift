// Copyright (C) 2022 Garth Vander Houwen

import SwiftUI
import CoreData
import OSLog
import TipKit
import MeshtasticProtobufs
import DatadogCore
import DatadogCrashReporting
import DatadogRUM
import DatadogTrace
import DatadogLogs

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

	init() {
		let persistenceController = PersistenceController.shared
		let appState = AppState(
			router: Router()
		)
		// Initialize Datadog
		// RUM Client Tokens are NOT secret
		let appID = "79fe92a9-74c9-4c8f-ba63-6308384ecfa9"
		let clientToken = "pub4427bea20dbdb08a6af68034de22cd3b"
		let environment = "testflight"

		Datadog.initialize(
			with: Datadog.Configuration(
				clientToken: clientToken,
				env: environment,
				site: .us5
			),
			trackingConsent: UserDefaults.usageDataAndCrashReporting ? .granted : .notGranted,
		)
		DatadogCrashReporting.CrashReporting.enable()
		Logs.enable()
		Trace.enable(
			with: Trace.Configuration(
				sampleRate: 100, networkInfoEnabled: true  // 100% sampling for development/testing, reduce for production
			)
		)

		RUM.enable(
			with: RUM.Configuration(
				applicationID: appID,
				uiKitViewsPredicate: DefaultUIKitRUMViewsPredicate(),
				uiKitActionsPredicate: DefaultUIKitRUMActionsPredicate(),
				trackBackgroundEvents: true
			)
		)
		self._appState = ObservedObject(wrappedValue: appState)
		// Initialize the BLEManager singleton with the necessary dependencies
		BLEManager.setup(appState: appState, context: persistenceController.container.viewContext)
		self.persistenceController = persistenceController
		// Wire up router
		self.appDelegate.router = appState.router
	#if DEBUG
		// Show tips in development
		try? Tips.resetDatastore()
	#endif
	}
    var body: some Scene {
        WindowGroup {
			ContentView(
				appState: appState,
				router: appState.router
			)
			.sheet(isPresented: Binding(
				get: {
					saveChannels && !(channelSettings == nil)
				},
				set: { newValue in
					saveChannels = newValue
					if !newValue {
						channelSettings = nil
					}
				}
			)) {
				SaveChannelQRCode(
					channelSetLink: channelSettings ?? "Empty Channel URL",
					addChannels: addChannels,
					bleManager: BLEManager.shared
				)
				.presentationDetents([.large])
				.presentationDragIndicator(.visible)
			}
			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
				Logger.mesh.debug("URL received \(userActivity, privacy: .public)")
				self.incomingUrl = userActivity.webpageURL
				self.saveChannels = false
				if self.incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/v/#") == true {
					ContactURLHandler.handleContactUrl(url: self.incomingUrl!, bleManager: BLEManager.shared)
				} else if self.incomingUrl?.absoluteString.lowercased().contains("meshtastic.org/e/") == true {
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
					ContactURLHandler.handleContactUrl(url: url, bleManager: BLEManager.shared)
				} else if url.absoluteString.lowercased().contains("meshtastic.org/e/") {
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
		.environment(\.managedObjectContext, persistenceController.container.viewContext)
		.environmentObject(appState)
		.environmentObject(BLEManager.shared)
	}

}
