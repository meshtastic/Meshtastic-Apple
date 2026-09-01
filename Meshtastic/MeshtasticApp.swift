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
	private let persistenceController: PersistenceController
	private let accessoryManager: AccessoryManager
	@Environment(\.scenePhase) var scenePhase
	@State var saveChannelLink: SaveChannelLinkData?
	@State var incomingUrl: URL?
	@State private var persistenceReady = false
	@State private var didStartReadyServices = false

	private static let isRunningTests = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
	private static let isChirpyOTADemo: Bool = {
		#if DEBUG
		return CommandLine.arguments.contains("--chirpy-ota-demo")
		#else
		return false
		#endif
	}()
	private static var shouldInitializeAppServices: Bool {
		!isRunningTests && !isChirpyOTADemo
	}
	/// TipKit configuration must run once per process; the owning `.task` re-runs whenever the
	/// database-reset gate remounts the main tree after a node switch.
	@MainActor private static var hasConfiguredTips = false

	init() {

#if DEBUG
		if let performanceSeedConfiguration = PerformanceSeedData.configuration {
			PerformanceSeedData.prepareDefaults(for: performanceSeedConfiguration)
		}
#endif

		let appState = AppState(
			router: Router()
		)

		if Self.shouldInitializeAppServices {
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
			// Report main-thread hangs over 2s as RUM errors with stacks. Unlike the long-task
			// observer this is a lightweight watchdog thread, and without it hang reports are
			// invisible — users report them by word of mouth and Datadog shows nothing.
			rumConfig.appHangThreshold = 2
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
		self.persistenceController = PersistenceController.shared

		// Wire up router
#if os(iOS)
		self.appDelegate.router = appState.router
#endif

	}

	@MainActor
	private func startReadyServicesIfNeeded() {
		guard Self.shouldInitializeAppServices,
			  persistenceReady,
			  !didStartReadyServices else { return }
		didStartReadyServices = true

#if DEBUG
		let performanceSeedConfiguration = PerformanceSeedData.configuration
		if let performanceSeedConfiguration {
			PerformanceSeedData.seedIfNeeded(
				using: persistenceController,
				configuration: performanceSeedConfiguration,
				router: appState.router
			)
		}
		PerformanceSeedData.seedDiscoveryBeaconsIfRequested(using: persistenceController)
		let performanceSeedDisablesDiscovery = performanceSeedConfiguration?.disableDiscovery == true
#else
		let performanceSeedDisablesDiscovery = false
#endif

		MapDataManager.shared.initialize()
		_ = WatchSessionManager.shared
#if os(iOS)
		TAKServerManager.shared.initializeOnStartup()
#endif
#if DEBUG
		if !CommandLine.arguments.contains("--marketing-capture") {
			try? Tips.resetDatastore()
		}
#endif
		if !UserDefaults.firstLaunch, !performanceSeedDisablesDiscovery {
			accessoryManager.startDiscovery()
		}
#if DEBUG
		let arguments = ProcessInfo.processInfo.arguments
		if let flagIndex = arguments.firstIndex(of: "-meshtastic-connect-tcp"),
		   arguments.indices.contains(flagIndex + 1),
		   let tcpTransport = accessoryManager.transportForType(.tcp),
		   let device = tcpTransport.device(forManualConnection: arguments[flagIndex + 1]) {
			let manager = accessoryManager
			Task {
				try? await Task.sleep(for: .seconds(2))
				Logger.services.info("🧪 [App] Auto-connecting to TCP device \(device.identifier, privacy: .public) (launch argument)")
				try? await manager.connect(to: device)
			}
		}
#endif
	}

	/// Single dispatch point for every URL the app receives — universal links
	/// (user activities), custom-scheme opens, and file opens all route here.
	private func dispatchIncomingURL(_ url: URL, fromActivity: Bool) {
		if url.isFileURL {
			// "Open in Meshtastic" from the Share Sheet / Files app / drag-and-drop —
			// distinct from the meshtastic:// scheme handled below.
			appState.router.importMapFile(url: url)
		} else if ContactURLHandler.canHandle(url) {
			ContactURLHandler.handleContactUrl(url: url, accessoryManager: accessoryManager)
		} else if MeshtasticChannelURL.canHandle(url) {
			handleChannelLinkURL(url, fromActivity: fromActivity)
		} else if url.absoluteString.lowercased().contains("meshtastic:///") {
			appState.router.route(url: url)
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
			} else if Self.isChirpyOTADemo {
				FirmwareUpdateGameDemoHost()
			} else if !persistenceReady {
				ProgressView("Updating local data…")
			} else if appState.isDatabaseResetting {
				// Unmount the WHOLE SwiftData-bound tree — including the `.modelContainer`
				// modifier in mainAppContent — while a node switch clears the store. The
				// modifier's SwiftData↔SwiftUI bridge observes save notifications process-wide
				// and never rebinds (its attachment point is structurally stable, so
				// `.id(databaseResetID)` deeper down can't recreate it); stale bridges from any
				// container the app has moved off of trap on the next save callout (the "silent
				// exit" flavor of Datadog 324bff02 — no crash report, EXC_BREAKPOINT in
				// _SwiftData_SwiftUI, caught live in lldb). This gate plus the process-lifetime
				// container (see backupCurrentAndRestoreDatabase) is the pair that ended it.
				DatabaseResettingPlaceholder()
			} else {
				mainAppContent
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
			.task {
				guard Self.shouldInitializeAppServices else { return }
				await persistenceController.bootstrap()
				persistenceReady = true
				startReadyServicesIfNeeded()
			}
		}
		.onChange(of: scenePhase) { (_, newScenePhase) in
			// Do not touch SwiftData until startup finishes or in modes that skip app services.
			guard Self.shouldInitializeAppServices, persistenceReady else { return }
			accessoryManager.isInBackground = (newScenePhase == .background)
			switch newScenePhase {
			case .background:
				Logger.services.info("🎬 [App] Scene is in the background")
				accessoryManager.appDidEnterBackground()
				// Entity-cap evictions run now, while no view is mid-render on the
				// doomed entities. Foregrounded, the packet actor defers them.
				MeshPackets.appIsActive = false
				Task { await MeshPackets.shared.enforceEntityCapsAndSave() }
				do {
					try persistenceController.container.mainContext.save()
					Logger.services.info("💾 [App] Saved SwiftData context when the app went to the background.")

				} catch {

					Logger.services.error("💥 [App] Failed to save context when the app goes to the background.")
				}
			case .inactive:
				Logger.services.info("🎬 [App] Scene is inactive")
			case .active:
				Logger.services.info("🎬 [App] Scene is active")
				MeshPackets.appIsActive = true
				accessoryManager.appDidBecomeActive()
				appState.refreshBadgeCount(context: persistenceController.container.mainContext)
			@unknown default:
				Logger.services.error("🍎 [App] Apple must have changed something")
			}
		}
		.environmentObject(appState)
		.environmentObject(accessoryManager)
		.environmentObject(lockdownCoordinator)
		.environmentObject(appState.router)

			WindowGroup("Mesh Map", id: "meshmap-window") {
				// Gated on app-service startup so test and demo modes never mount SwiftData views.
				// Also gated on the database reset, for the same stale-bridge reason as the main
				// window: this scene's .modelContainer must unmount during a container swap.
				if Self.shouldInitializeAppServices,
				   persistenceReady,
				   !appState.isDatabaseResetting {
					EventFirmwareTintScope {
						MapWindow()
							.id(appState.databaseResetID)
					}
					.modelContainer(persistenceController.container)
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

	/// The full SwiftData-bound app tree, extracted from the WindowGroup builder both to keep
	/// the scene-level expression type-checkable in reasonable time (the four-branch builder
	/// with this chain inlined blew Swift's type-check budget on CI) and so the database-reset
	/// gate can unmount it — `.modelContainer` included — as one unit.
	@ViewBuilder
	private var mainAppContent: some View {
		EventFirmwareTintScope {
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
					.sheet(item: $appState.pendingContactToAdd) { pendingContact in
						AddContactConfirmationView(
							pendingContact: pendingContact,
							accessoryManager: accessoryManager
						)
						.presentationDetents([.medium, .large])
						#if !targetEnvironment(macCatalyst)
						.presentationDragIndicator(.visible)
						#endif
					}
					.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
						Logger.mesh.debug("Browsing web user activity received")
						self.incomingUrl = userActivity.webpageURL
						self.saveChannelLink = nil

						if let url = userActivity.webpageURL {
							dispatchIncomingURL(url, fromActivity: true)
						}

						if self.saveChannelLink != nil {
							Logger.mesh.debug("User wants to open Channel Settings URL")
						}
					}
					.onOpenURL(perform: { (url) in
						Logger.mesh.debug("URL received")
						self.incomingUrl = url

						dispatchIncomingURL(url, fromActivity: false)
					})
					// Keep the badge in sync with read-state changes that happen outside
					// the message lists (Siri/CarPlay read-aloud, background ingest) —
					// previously those only reconciled on the next scene-active pass.
					.onReceive(
						NotificationCenter.default.publisher(for: .meshMessagesDidChange)
							.debounce(for: .seconds(1), scheduler: DispatchQueue.main)
					) { _ in
						appState.refreshBadgeCount(context: persistenceController.container.mainContext)
					}
				}
				.task {
					// Skip TipKit entirely during marketing screenshot capture so tip popovers never
					// appear in the shots (unconfigured TipKit displays nothing). The once-guard
					// matters now that this branch remounts after every node switch (the database
					// reset gate above) — Tips.configure must not re-run per switch.
					if !Self.hasConfiguredTips, !CommandLine.arguments.contains("--marketing-capture") {
						Self.hasConfiguredTips = true
						try? Tips.configure(
							[
								.datastoreLocation(.applicationDefault),
								// When should the tips be presented? If you use .immediate, they'll all be presented whenever a screen with a tip appears.
								// You can adjust this on per tip level as well
								.displayFrequency(.immediate)
							]
						)
					}
				}
				.modelContainer(persistenceController.container)
				.environmentObject(appState)
				.environmentObject(accessoryManager)
				.environmentObject(appState.router)
				.environmentObject(MeshtasticAPI.shared)
	}
}
