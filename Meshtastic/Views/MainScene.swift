import OSLog
import SwiftData
import SwiftUI
import TipKit

/// One main window. Owns that window's navigation. The database, the radio,
/// and the badge stay on `AppState` and are shared with every other window.
struct MainScene: View {
	let persistenceController: PersistenceController
	@StateObject private var router = Router()
	@StateObject private var nodeFilters = NodeFilterParameters()
	@EnvironmentObject private var appState: AppState
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.openWindow) private var openWindow
	#if os(visionOS) && DEBUG
	@Environment(\.openImmersiveSpace) private var openImmersiveSpace
	@Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
	/// `--meshtastic-open-showcase` (or `--meshtastic-open-cinema`) opens the space once per launch,
	/// not once per main window.
	private static var openedShowcaseForLaunchArgument = false
	#endif
	@State private var saveChannelLink: SaveChannelLinkData?
	@State private var pendingContact: PendingContact?
	@State private var routerToken: UUID?
	/// This window's scene, so a route from another window can bring it forward.
	@State private var sceneSession: UISceneSession?
	#if os(visionOS)
	/// The window's size and resizing before it became the cinema's screen. Kept until putting them
	/// back is seen to have worked, so a refused request is tried again.
	@State private var geometryBeforeCinema: UIWindowScene.GeometryPreferences.Vision?
	/// Whether this window has asked to be held at the cinema size.
	@State private var heldAtCinemaSize = false
	/// Tells this window's pose apart from other main windows' in the cinema.
	@State private var cinemaWindowID = UUID()
	#endif

	/// TipKit configuration must run once per process. This view stays mounted
	/// across node switches; the flag is a backstop if a window is recreated.
	private static var hasConfiguredTips = false

	var body: some View {
		sceneContent
			.background(SceneSessionReader(session: $sceneSession))
			#if os(visionOS)
			// In the cinema the tent's front wall is built around this window, wherever it is.
			.background {
				if appState.cinemaOpen {
					Color.clear
						.onGeometryChange(for: CinemaWindowPose?.self) { proxy in
							proxy.transform(in: .immersiveSpace).map { CinemaWindowPose(transform: $0, size: proxy.size) }
						} action: { pose in
							if let pose {
								appState.cinemaWindow.report(pose, from: cinemaWindowID)
							}
						}
						.onDisappear {
							appState.cinemaWindow.remove(cinemaWindowID)
						}
				}
			}
			#endif
			.environmentObject(router)
			.environmentObject(nodeFilters)
			.onAppear {
				if routerToken == nil {
					routerToken = appState.sceneRouters.register(router)
					appState.mainWindowCount += 1
					if let launch = appState.takeLaunchNavigation() {
						router.navigationState = launch
					}
				}
				// A notification can arrive before this window exists. `onChange`
				// does not replay the value it already holds.
				claimPendingRoute()
			}
			.onDisappear {
				guard let routerToken else { return }
				appState.sceneRouters.unregister(routerToken)
				self.routerToken = nil
				appState.mainWindowCount -= 1
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
			.onChange(of: appState.pendingRoute?.id) { _, _ in
				claimPendingRoute()
			}
			.onChange(of: scenePhase) { _, phase in
				if phase == .active {
					claimPendingRoute()
					#if os(visionOS)
					// Puts the size back if that was refused or skipped in the background.
					sizeForCinema()
					#endif
				}
			}
			#if os(visionOS)
			// In the cinema the window the front wall is built round is the screen.
			.onChange(of: isCinemaScreen, initial: true) { _, _ in
				sizeForCinema()
			}
			.onChange(of: sceneSession) { _, _ in
				sizeForCinema()
			}
			.onChange(of: router.spatialMapRequest?.id) { _, _ in
				guard let request = router.claimSpatialMapRequest() else { return }
				if let nodeNum = request.nodeNum {
					appState.spatialMapFocus = SpatialMapFocusRequest(nodeNum: nodeNum)
				}
				openWindow(id: SpatialMapScene.id, value: SpatialMapSceneKey.shared)
			}
			#endif
			#if os(visionOS) && DEBUG
			// Simulator screenshots: open the showcase without a button. Here rather than in the
			// app's init, because opening an immersive space needs a view's environment.
			.task {
				guard !Self.openedShowcaseForLaunchArgument else { return }
				let arguments = CommandLine.arguments
				if arguments.contains("--meshtastic-open-showcase") {
					Self.openedShowcaseForLaunchArgument = true
					try? await Task.sleep(for: .seconds(3))
					await ShowcaseScene.open(openImmersiveSpace, dismissImmersiveSpace: dismissImmersiveSpace, appState: appState)
				} else if arguments.contains("--meshtastic-open-cinema") {
					Self.openedShowcaseForLaunchArgument = true
					try? await Task.sleep(for: .seconds(3))
					await CinemaScene.open(openImmersiveSpace, dismissImmersiveSpace: dismissImmersiveSpace, appState: appState)
				}
			}
			#endif
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
			ContentView(
				appState: appState,
				router: router
			)
			.id(appState.databaseResetID)
			#if os(visionOS)
			.spatialFeaturesOrnament()
			#endif
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
			.alert("Couldn't Import Map File", isPresented: Binding(
				get: { router.mapImportError != nil },
				set: { if !$0 { router.mapImportError = nil } }
			)) {
				Button("OK", role: .cancel) { router.mapImportError = nil }
			} message: {
				Text(router.mapImportError ?? "")
			}
			// Badge refresh reads the store, so it has to unmount with the
			// container during a node switch. Message lists, Siri, and CarPlay
			// all post this.
			.onReceive(
				NotificationCenter.default.publisher(for: .meshMessagesDidChange)
					.debounce(for: .seconds(1), scheduler: DispatchQueue.main)
			) { _ in
				appState.refreshBadgeCount(context: persistenceController.container.mainContext)
			}
		}
		.modelContainer(persistenceController.container)
		.environmentObject(appState)
		.environmentObject(accessoryManager)
		.environmentObject(router)
		.environmentObject(nodeFilters)
		.environmentObject(MeshtasticAPI.shared)
	}

	#if os(visionOS)
	/// The window's size in the cinema, in points. The system grows a window with its distance, so
	/// this is close to a fixed angle: about 59° by 36°. The tent's front wall is 90° wide and, from
	/// the seat, runs from the floor 22° below the eye to the eave 16° above it and the ridge 33°
	/// above, so a window about level with the eye leaves wall showing all round it. The wall image
	/// carries on over the floor to 35° below the eye, so a window lowered by 15° still sits on the
	/// tent. 2400 by 1350 filled 81° and nearly covered the wall.
	private static let cinemaSize = CGSize(width: 1600, height: 900)

	/// Whether this window is the one the cinema's front wall is built round.
	private var isCinemaScreen: Bool {
		appState.cinemaOpen && appState.cinemaWindow.owner == cinemaWindowID
	}

	/// While this window is the cinema's screen it is held at the cinema size, so the frame and
	/// wall built round it fit. Its size and resizing are put back afterwards. Locking the screen
	/// only hides the bar that moves it.
	private func sizeForCinema() {
		guard let windowScene = sceneSession?.scene as? UIWindowScene else { return }
		if isCinemaScreen {
			guard !heldAtCinemaSize else { return }
			// Saved only once: if a restore never went through, this is still the size from before.
			if geometryBeforeCinema == nil {
				let geometry = windowScene.effectiveGeometry
				geometryBeforeCinema = .init(
					size: geometry.coordinateSpace.bounds.size,
					minimumSize: geometry.minimumSize,
					maximumSize: geometry.maximumSize,
					resizingRestrictions: Self.restrictions(geometry.resizingRestrictions)
				)
			}
			heldAtCinemaSize = true
			let size = Self.cinemaSize
			requestGeometry(.init(size: size, minimumSize: size, maximumSize: size, resizingRestrictions: UIWindowScene.ResizingRestrictions.none), in: windowScene)
		} else if let geometryBeforeCinema {
			heldAtCinemaSize = false
			requestGeometry(geometryBeforeCinema, in: windowScene)
			Task {
				// The request only reports failure, so look at the window a moment later.
				try? await Task.sleep(for: .seconds(1))
				guard !isCinemaScreen, self.geometryBeforeCinema != nil else { return }
				let geometry = windowScene.effectiveGeometry
				if geometry.resizingRestrictions == .none, geometry.maximumSize == Self.cinemaSize {
					Logger.services.info("🎬 [Cinema] The window is still at the cinema size; trying again when it is next active")
				} else {
					self.geometryBeforeCinema = nil
				}
			}
		}
	}

	/// The geometry reports its resizing as the Objective-C type; preferences take the Swift one.
	private static func restrictions(_ value: UIWindowSceneResizingRestrictions) -> UIWindowScene.ResizingRestrictions {
		switch value {
		case .none: .none
		case .uniform: .uniform
		case .freeform: .freeform
		@unknown default: .freeform
		}
	}

	private func requestGeometry(_ preferences: UIWindowScene.GeometryPreferences.Vision, in windowScene: UIWindowScene) {
		windowScene.requestGeometryUpdate(preferences) { error in
			Logger.services.error("🎬 [Cinema] Couldn't resize the window: \(error.localizedDescription, privacy: .public)")
		}
	}
	#endif

	/// Notification taps land on `AppState` because the app delegate has no
	/// window. This window takes the route only while it is active, and clears
	/// it so another window does not navigate too.
	private func claimPendingRoute() {
		guard scenePhase == .active else { return }
		guard let route = appState.claimPendingRoute() else { return }
		if route.bringForward, let sceneSession {
			UIApplication.shared.requestSceneSessionActivation(sceneSession, userActivity: nil, options: nil) { error in
				Logger.services.error("🛣 [App] Couldn't bring the window forward: \(error.localizedDescription, privacy: .public)")
			}
		}
		dispatchIncomingURL(route.url, fromActivity: false)
	}

	private func dispatchIncomingURL(_ url: URL, fromActivity: Bool) {
		if url.isFileURL {
			router.importMapFile(url: url)
		} else if ContactURLHandler.canHandle(url) {
			if let pending = ContactURLHandler.makePendingContact(from: url, accessoryManager: accessoryManager) {
				pendingContact = pending
			}
		} else if MeshtasticChannelURL.canHandle(url) {
			handleChannelLinkURL(url, fromActivity: fromActivity)
		} else if url.absoluteString.lowercased().contains("meshtastic:///") {
			router.route(url: url)
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

/// Reads the UIKit scene session of the window it is placed in.
private struct SceneSessionReader: UIViewRepresentable {
	@Binding var session: UISceneSession?

	func makeUIView(context: Context) -> ReaderView {
		let view = ReaderView()
		view.onWindow = { session = $0 }
		return view
	}

	func updateUIView(_ uiView: ReaderView, context: Context) {}

	final class ReaderView: UIView {
		var onWindow: ((UISceneSession?) -> Void)?

		override func didMoveToWindow() {
			super.didMoveToWindow()
			let session = window?.windowScene?.session
			DispatchQueue.main.async { [onWindow] in onWindow?(session) }
		}
	}
}
