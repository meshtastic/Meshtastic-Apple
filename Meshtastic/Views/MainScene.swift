import OSLog
import SwiftData
import SwiftUI
import TipKit

/// One main window. Owns that window's navigation. The database, the radio,
/// and the badge stay on `AppState` and are shared with every other window.
///
/// On the Mac with radio windows (feature 021, D-19) this is the Connect window, and each
/// radio has its own window (`RadioWindowRoot`). Elsewhere it shows the app for the radio
/// this window works with (`OneWindowRadioScope`); `ContentView` registers the router with
/// `AppState.windows`, which deep links and notification taps go through (T308).
struct MainScene: View {
	let persistenceController: PersistenceController
	@StateObject private var router = Router()
	@StateObject private var nodeFilters = NodeFilterParameters()
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@State private var saveChannelLink: SaveChannelLinkData?
	@State private var pendingContact: PendingContact?
	@State private var tookLaunchNavigation = false

	/// TipKit configuration must run once per process. This view stays mounted
	/// across node switches; the flag is a backstop if a window is recreated.
	private static var hasConfiguredTips = false

	var body: some View {
		sceneContent
			.environmentObject(router)
			.environmentObject(nodeFilters)
			.onAppear {
				if !tookLaunchNavigation {
					tookLaunchNavigation = true
					if let launch = appState.takeLaunchNavigation() {
						router.navigationState = launch
					}
				}
			}
			.onOpenURL { url in
				Logger.mesh.debug("URL received")
				dispatchIncomingURL(url, fromActivity: false)
			}
			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
				Logger.mesh.debug("Browsing web user activity received")
				saveChannelLink = nil
				if let url = userActivity.webpageURL {
					dispatchIncomingURL(url, fromActivity: true)
				}
			}
			.task {
				// Skip TipKit during marketing screenshot capture so tip popovers never
				// appear in the shots (unconfigured TipKit displays nothing).
				if !Self.hasConfiguredTips, !CommandLine.arguments.contains("--marketing-capture") {
					Self.hasConfiguredTips = true
					try? Tips.configure(
						[
							.datastoreLocation(.applicationDefault),
							.displayFrequency(.immediate)
						]
					)
				}
			}
	}

	@ViewBuilder
	private var sceneContent: some View {
		if appState.isDatabaseResetting {
			// Unmount the SwiftData-bound tree — including `.modelContainer` —
			// while a node switch clears the store. The modifier's bridge
			// observes save notifications process-wide and never rebinds; a
			// stale bridge traps on the next save (Datadog 324bff02). The
			// router stays on this view, above the gate, so the window keeps
			// its tab.
			DatabaseResettingPlaceholder()
		} else {
			loadedContent
		}
	}

	private var loadedContent: some View {
		EventFirmwareTintScope {
			Group {
				if RadioWindows.areEnabled {
					// On the Mac this is the Connect window; each radio has its own (W-02).
					RadioListWindow()
						.modifier(RadioWindowOpener(tracker: appState.radioWindowTracker))
				} else {
					OneWindowRadioScope {
						ContentView(
							appState: appState,
							router: router
						)
					}
				}
			}
			.id(appState.databaseResetID)
			.sheet(item: $saveChannelLink) { link in
				SaveChannelQRCode(
					channelSetLink: link.data,
					addChannels: link.add,
					accessoryManager: accessoryManager
				)
				.trackScreen(.saveChannelQRCode)
				.presentationDetents([.large])
				#if !targetEnvironment(macCatalyst)
				.presentationDragIndicator(.visible)
				#endif
			}
			.contactImportSheet($pendingContact, accessoryManager: accessoryManager)
		}
		.modelContainer(persistenceController.container)
		.environmentObject(appState)
		.environmentObject(accessoryManager)
		.environmentObject(router)
		.environmentObject(nodeFilters)
		.environmentObject(MeshtasticAPI.shared)
	}

	private func dispatchIncomingURL(_ url: URL, fromActivity: Bool) {
		if url.isFileURL {
			// "Open in Meshtastic" from the Share Sheet, Files or drag and drop: the window the
			// user was last in, which on the Mac is a radio's window rather than this one.
			(appState.windows.router(for: url, manager: accessoryManager) ?? router).importMapFile(url: url)
		} else if ContactURLHandler.canHandle(url) {
			if let pending = ContactURLHandler.makePendingContact(from: url, accessoryManager: accessoryManager) {
				pendingContact = pending
			}
		} else if MeshtasticChannelURL.canHandle(url) {
			handleChannelLinkURL(url, fromActivity: fromActivity)
		} else if url.absoluteString.lowercased().contains("meshtastic:///") {
			// The window of the radio the link is about (W-05).
			appState.windows.route(url: url, manager: accessoryManager)
		}
	}

	@discardableResult
	private func handleChannelLinkURL(_ url: URL, fromActivity: Bool) -> Bool {
		saveChannelLink = nil

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

		saveChannelLink = SaveChannelLinkData(data: channelLink.payload, add: channelLink.addChannels)
		Logger.services.debug("Add Channel \(channelLink.addChannels, privacy: .public)")

		let source = fromActivity ? "User Activity" : "Open URL"
		Logger.mesh.debug("User wants to open a Channel Settings URL (\(source, privacy: .public))")
		return true
	}
}
