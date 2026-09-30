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
	init() {

		let persistenceController: PersistenceController? = Self.shouldInitializeAppServices ? PersistenceController.shared : nil
#if DEBUG
		if let performanceSeedConfiguration = PerformanceSeedData.configuration {
			PerformanceSeedData.prepareDefaults(for: performanceSeedConfiguration)
		}
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

	}

	@MainActor
	private func startReadyServicesIfNeeded(using persistenceController: PersistenceController) {
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
				appState: appState
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

	/// Runs the work the app owes at backgrounding — the main-context save, then the
	/// entity-cap eviction — under one background task assertion.
	///
	/// `beginBackgroundTask` is what asks iOS for time to finish work after the app leaves
	/// the screen. Both pieces need it: between them they are the app's heaviest SwiftData
	/// work and they start at the moment iOS begins charging for background CPU. The
	/// expiration handler fires shortly before the grant runs out and sets the flag the
	/// chunked eviction checks, so the pass ends at a committed boundary and whatever is
	/// left waits for the next background transition.
	///
	/// The save goes first and stays on the main actor: it is the one that must happen (it
	/// is flushing edits the user just made), while the eviction is housekeeping that can
	/// resume later.
	///
	/// On Mac Catalyst the assertion is a no-op the system accepts, so the same path runs
	/// everywhere without a platform branch here.
	private func startBackgroundMaintenance(_ persistenceController: PersistenceController) {
		// Numbered, because backgrounding twice in quick succession leaves two passes in
		// flight and each has its own grant. The handler quotes its own number so an older
		// pass expiring cannot stop a newer one.
		let generation = MeshPackets.beginMaintenance()
		var taskID = UIBackgroundTaskIdentifier.invalid
		taskID = UIApplication.shared.beginBackgroundTask(withName: "BackgroundMaintenance") {
			MeshPackets.expireMaintenance(generation)
			Logger.services.warning("🗄️ [Caps] Background time expired; eviction will stop at the next chunk")
		}
		Task { @MainActor in
			do {
				try persistenceController.container.mainContext.save()
				Logger.services.info("💾 [App] Saved SwiftData context when the app went to the background.")
			} catch {
				Logger.services.error("💥 [App] Failed to save context when the app goes to the background.")
			}
			await MeshPackets.shared.enforceEntityCapsAndSave()
			// Nothing to clear: the next pass takes a new number, which supersedes any
			// expiry recorded against this one.
			if taskID != .invalid {
				UIApplication.shared.endBackgroundTask(taskID)
			}
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
			} else if !persistenceReady {
				ProgressView("Updating local data…")
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
			.task {
				guard Self.shouldInitializeAppServices, let persistenceController else { return }
				await persistenceController.bootstrap()
				persistenceReady = true
				startReadyServicesIfNeeded(using: persistenceController)
			}
		}
		.onChange(of: scenePhase) { (_, newScenePhase) in
			// Do not touch SwiftData until startup finishes or in modes that skip app services.
			guard Self.shouldInitializeAppServices, persistenceReady, let persistenceController else { return }
			accessoryManager.isInBackground = (newScenePhase == .background)
			switch newScenePhase {
			case .background:
				Logger.services.info("🎬 [App] Scene is in the background")
				accessoryManager.appDidEnterBackground()
				// Entity-cap evictions run now, while no view is mid-render on the
				// doomed entities. Foregrounded, the packet actor defers them.
				//
				// Held under a background task assertion: this is the app's heaviest
				// SwiftData work and it starts at the moment iOS begins charging for
				// background CPU. Without the assertion there is no time granted and no
				// warning before the process is killed for the budget, which reads as a
				// Background High CPU termination. The expiration handler stops the
				// eviction on a committed chunk boundary instead.
				MeshPackets.appIsActive = false
				startBackgroundMaintenance(persistenceController)
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
				// Gated on app-service startup so test and demo modes never mount SwiftData views.
				// Also gated on the database reset, for the same stale-bridge reason as the main
				// window: this scene's .modelContainer must unmount during a container swap.
				if Self.shouldInitializeAppServices,
				   persistenceReady,
				   let persistenceController,
				   !appState.isDatabaseResetting {
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
