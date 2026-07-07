// Copyright (C) 2022 Garth Vander Houwen

import SwiftUI
import SwiftData
import OSLog
import TipKit
import MeshtasticProtobufs
import WatchConnectivity
import DatadogCore
import DatadogCrashReporting
import DatadogRUM
import DatadogTrace
import DatadogLogs

@main
struct MeshtasticAppleApp: App {

#if os(iOS)
	@UIApplicationDelegateAdaptor(MeshtasticAppDelegate.self) private var appDelegate
#endif
	@StateObject var appState: AppState
	@StateObject private var lockdownCoordinator: LockdownCoordinator
	private let persistenceController: PersistenceController?
	private let accessoryManager: AccessoryManager
	@Environment(\.scenePhase) var scenePhase
	@State var saveChannelLink: SaveChannelLinkData?
	@State var incomingUrl: URL?

	private static let isRunningTests = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

	init() {

		let persistenceController: PersistenceController? = Self.isRunningTests ? nil : PersistenceController.shared
#if DEBUG
		let performanceSeedConfiguration = PerformanceSeedData.configuration
		if let performanceSeedConfiguration {
			PerformanceSeedData.prepareDefaults(for: performanceSeedConfiguration)
		}
		let performanceSeedDisablesDiscovery = performanceSeedConfiguration?.disableDiscovery == true
#else
		let performanceSeedDisablesDiscovery = false
#endif

		let appState = AppState(
			router: Router()
		)

		if !Self.isRunningTests {
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
					sampleRate: 20, networkInfoEnabled: true
				)
			)

			var rumConfig = RUM.Configuration(
				applicationID: appID,
				swiftUIViewsPredicate: DefaultSwiftUIRUMViewsPredicate(),
				swiftUIActionsPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true),
				trackBackgroundEvents: true
			)
			// Disable expensive continuous monitoring to reduce idle CPU (~15% savings)
			rumConfig.longTaskThreshold = nil  // Disables LongTaskObserver CFRunLoop hook
			rumConfig.vitalsUpdateFrequency = nil    // Disables VitalRefreshRateReader display link
			RUM.enable(with: rumConfig)

		}

		accessoryManager = AccessoryManager.shared
		accessoryManager.appState = appState

		// Lockdown coordinator. Constructed here so it lives at app scope and is
		// injected into the SwiftUI environment for views to observe. The sender
		// is wired after construction to avoid an init-time cycle with AccessoryManager.
		let lockdown = LockdownCoordinator()
		lockdown.setSender(accessoryManager)
		accessoryManager.lockdownCoordinator = lockdown
		self._lockdownCoordinator = StateObject(wrappedValue: lockdown)

		self._appState = StateObject(wrappedValue: appState)

		self.persistenceController = persistenceController
		// Wire up router
#if os(iOS)
		self.appDelegate.router = appState.router
#endif

#if DEBUG
		if let persistenceController, let performanceSeedConfiguration {
			PerformanceSeedData.seedIfNeeded(
				using: persistenceController,
				configuration: performanceSeedConfiguration,
				router: appState.router
			)
		}
		// Independent of the node performance seed: seeds a sample Discovery session with beacons
		// when launched with --meshtastic-seed-beacons, without resetting the store or blocking a
		// live radio connection.
		if let persistenceController {
			PerformanceSeedData.seedDiscoveryBeaconsIfRequested(using: persistenceController)
		}
#endif

		if !Self.isRunningTests {
			// Initialize map data manager
			MapDataManager.shared.initialize()

			// Initialize WatchConnectivity session
			_ = WatchSessionManager.shared
#if DEBUG
			// Show tips in development — but not during marketing screenshot capture, where TipKit
			// popovers would clutter the shots.
			if !CommandLine.arguments.contains("--marketing-capture") {
				try? Tips.resetDatastore()
			}
#endif
			if !UserDefaults.firstLaunch {
				// If this is first launch, we will show onboarding screens which
				// Step through the authorization process. Do not start discovery
				// unitl this workflow completes, otherwise the discovery process
			// may trigger permission dialogs too soon.
				if !performanceSeedDisablesDiscovery {
					accessoryManager.startDiscovery()
				}
			}
		}
	}

	@discardableResult
	private func handleChannelLinkURL(_ url: URL, fromActivity: Bool) -> Bool {
		// Reset the state before processing a new URL
		self.saveChannelLink = nil

		guard MeshtasticChannelURL.canHandle(url) else {
			return false
		}

		let channelLink: MeshtasticChannelURL
		do {
			channelLink = try MeshtasticChannelURL.parse(url.absoluteString)
		} catch {
			Logger.mesh.error("Could not parse channel URL: \(error.localizedDescription, privacy: .public)")
			return false
		}

		self.saveChannelLink = SaveChannelLinkData(data: channelLink.payload, add: channelLink.addChannels)
		Logger.services.debug("Add Channel \(channelLink.addChannels, privacy: .public)")

		// Log based on the calling context
		let source = fromActivity ? "User Activity" : "Open URL"
		Logger.mesh.debug("User wants to open a Channel Settings URL (\(source, privacy: .public))")
		return true
	}

	var body: some Scene {
		WindowGroup {
			Group {
			if Self.isRunningTests {
				Color.clear
			} else {
				ContentView(
					appState: appState,
					router: appState.router
				)
				// Rebuild the whole view tree (and re-run every @Query) after a node-switch
				// restore so views drop the previous node's cached objects. See AppState.databaseResetID.
				.id(appState.databaseResetID)
				.sheet(item: $saveChannelLink
				) { link in
					SaveChannelQRCode(
						channelSetLink: link.data,
						addChannels: link.add, // <-- Uses the now reliable 'add' boolean
						accessoryManager: accessoryManager				)
					.presentationDetents([.large])
					#if !targetEnvironment(macCatalyst)
					.presentationDragIndicator(.visible)
					#endif
					}
					.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
						Logger.mesh.debug("Browsing web user activity received")
						self.incomingUrl = userActivity.webpageURL
						self.saveChannelLink = nil

						if let url = userActivity.webpageURL {
							if url.absoluteString.lowercased().contains("meshtastic.org/v/#") == true {
								ContactURLHandler.handleContactUrl(url: url, accessoryManager: accessoryManager)
							} else if MeshtasticChannelURL.canHandle(url) {
								// **Consolidated Call for User Activity**
								handleChannelLinkURL(url, fromActivity: true)
							}
						}

						if self.saveChannelLink != nil {
							Logger.mesh.debug("User wants to open Channel Settings URL")
						}
					}
					.onOpenURL(perform: { (url) in
						Logger.mesh.debug("URL received")
						self.incomingUrl = url

						if url.isFileURL {
							// "Open in Meshtastic" from the Share Sheet / Files app / drag-and-drop —
							// distinct from the meshtastic:// scheme handled below.
							appState.router.importMapFile(url: url)
						} else if url.absoluteString.lowercased().contains("meshtastic.org/v/#") {
							ContactURLHandler.handleContactUrl(url: url, accessoryManager: accessoryManager)
						} else if MeshtasticChannelURL.canHandle(url) {
							// **Consolidated Call for Open URL**
							handleChannelLinkURL(url, fromActivity: false)
						} else if url.absoluteString.lowercased().contains("meshtastic:///") {
							appState.router.route(url: url)
						}
					})
				.task {
					// Skip TipKit entirely during marketing screenshot capture so tip popovers never
					// appear in the shots (unconfigured TipKit displays nothing).
					if !CommandLine.arguments.contains("--marketing-capture") {
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
				.modelContainer(persistenceController!.container)
				.environmentObject(appState)
				.environmentObject(accessoryManager)
				.environmentObject(appState.router)
				.environmentObject(MeshtasticAPI.shared)
			}
			}
			.onChange(of: lockdownCoordinator.state) { _, newState in
				// US-3: when the coordinator resolves to .lockNowAcknowledged
				// (either via inbound LOCKED status or a BLE disconnect race),
				// tear down the connection so the next reconnect re-auths.
				if case .lockNowAcknowledged = newState {
					Task { try? await accessoryManager.closeConnection() }
				}
			}
		}
		.onChange(of: scenePhase) { (_, newScenePhase) in
			guard !Self.isRunningTests else { return }
			accessoryManager.isInBackground = (newScenePhase == .background)
			switch newScenePhase {
			case .background:
				Logger.services.info("🎬 [App] Scene is in the background")
				accessoryManager.appDidEnterBackground()
				do {
					try persistenceController!.container.mainContext.save()
					Logger.services.info("💾 [App] Saved SwiftData context when the app went to the background.")

				} catch {

					Logger.services.error("💥 [App] Failed to save context when the app goes to the background.")
				}
			case .inactive:
				Logger.services.info("🎬 [App] Scene is inactive")
			case .active:
				Logger.services.info("🎬 [App] Scene is active")
				accessoryManager.appDidBecomeActive()
				if let context = persistenceController?.container.mainContext {
					appState.refreshBadgeCount(context: context)
				}
			@unknown default:
				Logger.services.error("🍎 [App] Apple must have changed something")
			}
		}
		.environmentObject(appState)
		.environmentObject(accessoryManager)
		.environmentObject(lockdownCoordinator)
		.environmentObject(appState.router)
		.environmentObject(MeshtasticAPI.shared)

		WindowGroup("Mesh Map", id: "meshmap-window") {
			if !Self.isRunningTests {
				MapWindow()
					.id(appState.databaseResetID)
					.modelContainer(persistenceController!.container)
					.environmentObject(appState)
					.environmentObject(accessoryManager)
					.environmentObject(lockdownCoordinator)
					.environmentObject(appState.router)
					.environmentObject(MeshtasticAPI.shared)
			}
		}
		.handlesExternalEvents(matching: [])
		.windowResizability(.contentMinSize)
		#if os(visionOS)
		.windowStyle(.plain)
		#endif
	}
}
