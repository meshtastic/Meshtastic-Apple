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
	init() {

		let persistenceController: PersistenceController? = Self.shouldInitializeAppServices ? PersistenceController.shared : nil
#if DEBUG
		let performanceSeedConfiguration = PerformanceSeedData.configuration
		if let performanceSeedConfiguration {
			PerformanceSeedData.prepareDefaults(for: performanceSeedConfiguration)
		}
		let performanceSeedDisablesDiscovery = performanceSeedConfiguration?.disableDiscovery == true
#else
		let performanceSeedDisablesDiscovery = false
#endif

		let appState = AppState()

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
				swiftUIViewsPredicate: MeshtasticSwiftUIViewsPredicate(),
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

		self.persistenceController = persistenceController
#if os(iOS)
		self.appDelegate.appState = appState
#endif

#if DEBUG
		if let persistenceController, let performanceSeedConfiguration {
			PerformanceSeedData.seedIfNeeded(
				using: persistenceController,
				configuration: performanceSeedConfiguration,
				appState: appState
			)
		}
		// Independent of the node performance seed: seeds a sample Discovery session with beacons
		// when launched with --meshtastic-seed-beacons, without resetting the store or blocking a
		// live radio connection.
		if let persistenceController {
			PerformanceSeedData.seedDiscoveryBeaconsIfRequested(using: persistenceController)
		}
#endif

		if Self.shouldInitializeAppServices {
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
#if DEBUG
			// Automated perf/stress testing: connect straight to a TCP radio (or replay
			// server) with `-meshtastic-connect-tcp <host[:port]>`, skipping the Connect
			// tab entirely. DEBUG-only, like the other automation hooks above.
			let arguments = ProcessInfo.processInfo.arguments
			if let flagIndex = arguments.firstIndex(of: "-meshtastic-connect-tcp"),
			   arguments.indices.contains(flagIndex + 1),
			   let tcpTransport = accessoryManager.transportForType(.tcp),
			   let device = tcpTransport.device(forManualConnection: arguments[flagIndex + 1]) {
				let manager = accessoryManager
				Task {
					// Give startup (container, transports, discovery) a beat to settle.
					try? await Task.sleep(for: .seconds(2))
					Logger.services.info("🧪 [App] Auto-connecting to TCP device \(device.identifier, privacy: .public) (launch argument)")
					try? await manager.connect(to: device)
				}
			}
#endif
		}
	}

	var body: some Scene {
		WindowGroup {
			Group {
			if Self.isRunningTests {
				Color.clear
			} else if Self.isChirpyOTADemo {
				// Kept out of the release build's view type on purpose, not just behind a flag
				// that is false there: the automatic RUM view naming reflects over these
				// branches, and this type — which can never be on screen in release — was
				// being reported as the view for everything that happened at the app root.
				// See `trackScreen`.
				#if DEBUG
				FirmwareUpdateGameDemoHost()
				#endif
			} else if let persistenceController {
				// Stays mounted across a node switch so this window's router survives.
				// The SwiftData tree unmounts inside MainScene.
				MainScene(persistenceController: persistenceController)
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
			// Also skipped in Chirpy OTA demo mode, where persistenceController is nil —
			// backgrounding the demo must not touch (or force-unwrap) SwiftData.
			guard Self.shouldInitializeAppServices, let persistenceController else { return }
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
		.environmentObject(MeshtasticAPI.shared)

			WindowGroup("Mesh Map", id: "meshmap-window") {
				// Gated on shouldInitializeAppServices (not just tests): in Chirpy OTA demo mode
				// persistenceController is nil, so building this scene would force-unwrap-crash.
				// Also gated on the database reset, for the same stale-bridge reason as the main
				// window: this scene's .modelContainer must unmount during a container swap.
				if Self.shouldInitializeAppServices, let persistenceController, !appState.isDatabaseResetting {
					EventFirmwareTintScope {
						MapWindow()
							.id(appState.databaseResetID)
					}
					.modelContainer(persistenceController.container)
					.environmentObject(appState)
					.environmentObject(accessoryManager)
					.environmentObject(lockdownCoordinator)
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
