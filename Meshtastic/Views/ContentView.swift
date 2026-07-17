/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

struct ContentView: View {
	@ObservedObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var lockdown: LockdownCoordinator
	// Observe (not just hold) the router so a *programmatic* `selectedTab` change re-renders
	// ContentView and the TabView re-reads its selection binding immediately. As plain @State this
	// view never subscribed to the router's objectWillChange, so a programmatic tab switch only took
	// effect on the next incidental re-render (e.g. an unread-count change) — instant on a busy live
	// mesh, but a 20–60s stall in a quiet/seeded session.
	@ObservedObject var router: Router
	@State var isShowingDeviceOnboardingFlow: Bool = false

	/// True when the connected device's lockdown state requires the user to act
	/// (provision a passphrase, unlock, or wait out a backoff). The sheet is
	/// non-dismissable; it only closes when the coordinator transitions to a
	/// non-blocking state (.none, .unlocked, .lockNowAcknowledged).
	private var isLockdownGateActive: Bool { lockdown.isBlockingSession }

	/// Plain view-state mirror of `isLockdownGateActive`, kept in sync from the
	/// coordinator via `.onChange`. Presenting the lockdown `fullScreenCover`
	/// through a *computed* `Binding` — getter reading the `lockdown`
	/// `@EnvironmentObject`, setter a no-op — produced a presentation binding that
	/// could never converge, which iOS 17's SwiftUI resolved by re-entering the
	/// attribute graph until it tripped `_assertionFailure` at first layout (a
	/// launch crash unique to iOS 17; iOS 18+ tolerated it). Driving the cover
	/// from real `@State` breaks that cycle. `LockdownSheet` has no dismiss
	/// affordance, so this stays non-dismissable — only the coordinator leaving a
	/// blocking state clears it.
	@State private var isShowingLockdownGate: Bool = false

	init(appState: AppState, router: Router) {
		self.appState = appState
		self.router = router
	}

	var body: some View {
		tabContent
			.sheet(
				isPresented: $isShowingDeviceOnboardingFlow,
				onDismiss: {
					UserDefaults.firstLaunch = false
					accessoryManager.startDiscovery()
				}, content: {
					DeviceOnboarding()
				}
			)
			.fullScreenCover(isPresented: $isShowingLockdownGate) {
				LockdownSheet()
			}
			.onAppear {
				if UserDefaults.firstLaunch {
					isShowingDeviceOnboardingFlow = true
				}
				// Present the gate if the device is already in a blocking state when
				// this view appears.
				isShowingLockdownGate = isLockdownGateActive
			}
			.onChange(of: isLockdownGateActive) { _, active in
				// Follow the coordinator's blocking state. The gate never closes from
				// user interaction (fullScreenCover has no interactive dismiss and
				// LockdownSheet exposes no dismiss control), so this is the only path
				// that shows or hides it.
				isShowingLockdownGate = active
			}
			.onChange(of: UserDefaults.showDeviceOnboarding) {_, newValue in
				isShowingDeviceOnboardingFlow = newValue
			}
			.task {
#if DEBUG
				// No-op unless launched with --marketing-capture (see MarketingCapture / PerformanceSeedData).
				await MarketingCapture.runIfNeeded(router: router, accessoryManager: accessoryManager)
#endif
			}
	}

	// MARK: - Tab Reselection

	/// A custom binding that intercepts tab selection so that tapping the
	/// already-active tab pops its navigation stack back to root.
	private var tabSelection: Binding<NavigationState.Tab> {
		Binding(
			get: { appState.router.selectedTab },
			set: { newTab in
				if newTab == appState.router.selectedTab {
					appState.router.popToRoot(tab: newTab)
				}
				appState.router.selectedTab = newTab
			}
		)
	}

	// MARK: - Tab Content

	@ViewBuilder
	private var tabContent: some View {
		if #available(iOS 18.0, macCatalyst 18.0, *) {
			TabView(selection: tabSelection) {
				Tab("Messages", systemImage: "message", value: NavigationState.Tab.messages) {
					Messages(
						router: appState.router,
						unreadChannelMessages: $appState.unreadChannelMessages,
						unreadDirectMessages: $appState.unreadDirectMessages
					)
				}
				.badge(appState.totalUnreadMessages)

				Tab("Nodes", image: "custom.mesh.radio", value: NavigationState.Tab.nodes) {
					NodeList()
				}

				Tab("Map", systemImage: "map", value: NavigationState.Tab.map) {
					MeshMapMK(router: appState.router)
				}

				Tab("Settings", systemImage: "gear", value: NavigationState.Tab.settings) {
					Settings()
				}

				Tab("Connect", systemImage: "link", value: NavigationState.Tab.connect) {
					Connect(
						router: appState.router
					)
				}
			}
		} else {
			TabView(selection: tabSelection) {
				Messages(
					router: appState.router,
					unreadChannelMessages: $appState.unreadChannelMessages,
					unreadDirectMessages: $appState.unreadDirectMessages
				)
				.tabItem {
					Label("Messages", systemImage: "message")
				}
				.tag(NavigationState.Tab.messages)
				.badge(appState.totalUnreadMessages)

				NodeList()
				.tabItem {
					Label("Nodes", image: "custom.mesh.radio")
				}
				.tag(NavigationState.Tab.nodes)

				MeshMapMK(router: appState.router)
				.tabItem {
					Label("Map", systemImage: "map")
				}
				.tag(NavigationState.Tab.map)

				Settings()
				.tabItem {
					Label("Settings", systemImage: "gear")
				}
				.tag(NavigationState.Tab.settings)

				Connect(
					router: appState.router
				)
				.tabItem {
					Label("Connect", systemImage: "link")
				}
				.tag(NavigationState.Tab.connect)
			}
		}
	}
}
