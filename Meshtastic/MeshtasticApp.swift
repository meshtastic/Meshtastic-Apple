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
#if DEBUG
import DatadogSessionReplay
#endif

// MARK: - AppState Definition
@MainActor
class AppState: ObservableObject {
	@Published var unreadChannelMessages: Int = 0
	@Published var unreadDirectMessages: Int = 0
	@Published var activeSheet: Sheet? = nil
	
	enum Sheet: Identifiable {
		case channelSettings(channelSettings: String, addChannels: Bool)
		case deviceOnboarding
		
		var id: String {
			switch self {
			case .channelSettings(let channelSettings, let addChannels):
				return "channelSettings_\(channelSettings)_\(addChannels)"
			case .deviceOnboarding:
				return "deviceOnboarding"
			}
		}
	}
	
	var totalUnreadMessages: Int {
		unreadChannelMessages + unreadDirectMessages
	}
}

// MARK: - App
@main
struct MeshtasticAppleApp: App {

	@UIApplicationDelegateAdaptor(MeshtasticAppDelegate.self) private var appDelegate

	@StateObject private var appState = AppState()
	@StateObject private var accessoryManager = AccessoryManager.shared
	@StateObject private var router = Router()
	
	@Environment(\.scenePhase) private var scenePhase
	
	private let persistenceController = PersistenceController.shared
	
	init() {
		setupDatadog()
		
		self.appDelegate.router = router
		
		MapDataManager.shared.initialize()
		
		#if DEBUG
		try? Tips.resetDatastore()
		#endif
		
		if !UserDefaults.firstLaunch {
			accessoryManager.startDiscovery()
		}
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
					Logger.services.debug("URL received \(userActivity, privacy: .public)")
					if let url = userActivity.webpageURL {
						handleIncomingURL(url)
					}
				}
				.onOpenURL { url in
					Logger.services.debug("Some sort of URL was received \(url, privacy: .public)")
					handleIncomingURL(url)
				}
		}
		.onChange(of: scenePhase) { (_, newScenePhase) in
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
		.environmentObject(router)
	}
	
	// MARK: - Private Methods
	
	private func handleIncomingURL(_ url: URL) {
		let urlString = url.absoluteString.lowercased()
		
		if urlString.contains("meshtastic.org/v/#") {
			ContactURLHandler.handleContactUrl(url: url, accessoryManager: accessoryManager)
		} else if urlString.contains("meshtastic.org/e/") {
			if let components = urlString.components(separatedBy: "#").first {
				// Correctly use the subscript on the 'url' object here.
				let addChannels = url["add"].flatMap { Bool($0) } ?? false
				let channelSettings = components.components(separatedBy: "?").first
				
				if let cs = channelSettings {
					Logger.services.debug("User wants to open a Channel Settings URL: \(url.absoluteString, privacy: .public)")
					appState.activeSheet = .channelSettings(channelSettings: cs, addChannels: addChannels)
				}
			}
		} else if urlString.contains("meshtastic:///") {
			router.route(url: url)
		} else {
			Logger.services.warning("URL handler couldn't parse URL: \(url, privacy: .public)")
		}
	}
	
	private func setupDatadog() {
		#if !targetEnvironment(macCatalyst)
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
				sampleRate: 100, networkInfoEnabled: true
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
		
		let attributes: [String: Encodable] = [
			"firmware_version": UserDefaults.firmwareVersion,
			"hardware_model": UserDefaults.hardwareModel
		]
		RUMMonitor.shared().addAttributes(attributes)
		#if DEBUG
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
		#endif
		#endif
	}
}
