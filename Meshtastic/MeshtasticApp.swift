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
import DatadogSessionReplay

@main
struct MeshtasticAppleApp: App {

	@UIApplicationDelegateAdaptor(MeshtasticAppDelegate.self) private var appDelegate
	@StateObject var appState: AppState
	private let persistenceController: PersistenceController
	private let accessoryManager: AccessoryManager
	@Environment(\.scenePhase) var scenePhase
	@State var saveChannelLink: SaveChannelLinkData?
	@State var incomingUrl: URL?

	init() {

		let persistenceController = PersistenceController.shared

		let appState = AppState(
			router: Router()
		)
		// Initialize Datadog
		// RUM Client Tokens are NOT secret
		let appID = "79fe92a9-74c9-4c8f-ba63-6308384ecfa9"
		let clientToken = "pub4427bea20dbdb08a6af68034de22cd3b"
		var environment = "AppStore"

#if DEBUG
		environment = "Local"
#else
		if Bundle.main.isTestFlight {
			environment = "TestFlight"
		}
#endif

		Datadog.initialize(
			with: Datadog.Configuration(
				clientToken: clientToken,
				env: environment,
				site: .us5
			),
			trackingConsent: UserDefaults.usageDataAndCrashReporting ? .granted : .notGranted
		)
		DatadogCrashReporting.CrashReporting.enable()
		Logs.enable()
		Trace.enable(
			with: Trace.Configuration(
				sampleRate: 100, networkInfoEnabled: true // 100% sampling for development/testing, reduce for production
			)
		)

		RUM.enable(
			with: RUM.Configuration(
				applicationID: appID,
				swiftUIViewsPredicate: DefaultSwiftUIRUMViewsPredicate(),
				swiftUIActionsPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true),
				trackBackgroundEvents: true
			)
		)
		if Bundle.main.isTestFlight {
			SessionReplay.enable(
				with: SessionReplay.Configuration(
					replaySampleRate: 100,
					textAndInputPrivacyLevel: .maskSensitiveInputs,
					imagePrivacyLevel: .maskNone,
					touchPrivacyLevel: .show,
					startRecordingImmediately: true,
					featureFlags: [.swiftui: true]
				)
			)
		}
		accessoryManager = AccessoryManager.shared
		accessoryManager.appState = appState

		self._appState = StateObject(wrappedValue: appState)

		self.persistenceController = persistenceController
		// Wire up router
		self.appDelegate.router = appState.router

		// Initialize map data manager
		MapDataManager.shared.initialize()
#if DEBUG
		// Show tips in development
		try? Tips.resetDatastore()
#endif
		if !UserDefaults.firstLaunch {
			// If this is first launch, we will show onboarding screens which
			// Step through the authorization process. Do not start discovery
			// unitl this workflow completes, otherwise the discovery process
			// may trigger permission dialogs too soon.
			accessoryManager.startDiscovery()
		}
	}

	private func handleChannelLinkURL(_ url: URL, fromActivity: Bool) {
		// Reset the state before processing a new URL
		self.saveChannelLink = nil

		guard url.absoluteString.lowercased().contains("meshtastic.org/e/") else {
			return
		}

		let queryParams = url.queryParameters
		let addChannels = Bool(queryParams?["add"] ?? "false") ?? false
		var channelData: String?
		let urlString = url.absoluteString

		if let fragment = urlString.components(separatedBy: "#").last, !fragment.isEmpty {
			channelData = fragment.components(separatedBy: "?").first
		}
		
		guard let finalChannelData = channelData, !finalChannelData.isEmpty else {
			Logger.mesh.error("Could not extract channel data from URL: \(url.absoluteString, privacy: .public)")
			return
		}

		self.saveChannelLink = SaveChannelLinkData(data: finalChannelData, add: addChannels)
		Logger.services.debug("Add Channel \(addChannels, privacy: .public) with data: \(finalChannelData, privacy: .public)")
		
		// Log based on the calling context
		let source = fromActivity ? "User Activity" : "Open URL"
		Logger.mesh.debug("User wants to open a Channel Settings URL (\(source)): \(url.absoluteString, privacy: .public)")
	}
	
	var body: some Scene {
		WindowGroup {
			ContentView(
				appState: appState,
				router: appState.router
			)
			.sheet(item: $saveChannelLink
			) { link in
				SaveChannelQRCode(
					channelSetLink: link.data,
					addChannels: link.add, // <-- Uses the now reliable 'add' boolean
					accessoryManager: accessoryManager				)
				.presentationDetents([.large])
				.presentationDragIndicator(.visible)
			}
			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
				Logger.mesh.debug("URL received \(userActivity, privacy: .public)")
				self.incomingUrl = userActivity.webpageURL
				self.saveChannelLink = nil

				if let url = userActivity.webpageURL {
					if url.absoluteString.lowercased().contains("meshtastic.org/v/#") == true {
						ContactURLHandler.handleContactUrl(url: url, accessoryManager: accessoryManager)
					} else if url.absoluteString.lowercased().contains("meshtastic.org/e/") == true {
						// **Consolidated Call for User Activity**
						handleChannelLinkURL(url, fromActivity: true)
					}
				}

				if self.saveChannelLink != nil {
					Logger.mesh.debug("User wants to open Channel Settings URL: \(String(describing: self.incomingUrl!.relativeString), privacy: .public)")
				}
			}
			.onOpenURL(perform: { (url) in
				Logger.mesh.debug("Some sort of URL was received \(url, privacy: .public)")
				self.incomingUrl = url
				
				if url.absoluteString.lowercased().contains("meshtastic.org/v/#") {
					ContactURLHandler.handleContactUrl(url: url, accessoryManager: accessoryManager)
				} else if url.absoluteString.lowercased().contains("meshtastic.org/e/") {
					// **Consolidated Call for Open URL**
					handleChannelLinkURL(url, fromActivity: false)
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
			accessoryManager.isInBackground = (newScenePhase == .background)
			switch newScenePhase {
			case .background:
				Logger.services.info("🎬 [App] Scene is in the background")
				accessoryManager.appDidEnterBackground()
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
				accessoryManager.appDidBecomeActive()
			@unknown default:
				Logger.services.error("🍎 [App] Apple must have changed something")
			}
		}
		.environment(\.managedObjectContext, persistenceController.container.viewContext)
		.environmentObject(appState)
		.environmentObject(accessoryManager)
	}
}
