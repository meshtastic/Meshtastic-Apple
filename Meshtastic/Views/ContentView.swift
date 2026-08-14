/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI
import SwiftData
import UIKit

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
	@State private var isShowingEventFirmwareInfo: Bool = false

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
		gatedContent
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
				// Trust the first-launch flag only when this process can actually read it. Launched
				// in the background before the phone's first unlock (Bluetooth state restoration
				// after a reboot), UserDefaults is still encrypted and `firstLaunch` returns its
				// default `true` — which re-ran the whole setup wizard on an installed app (#2243).
				// A pre-unlock launch can never be a genuine first launch: a fresh install has no
				// restoration session to be relaunched for.
				if UserDefaults.firstLaunch && UIApplication.shared.isProtectedDataAvailable {
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
				MarketingCapture.simulateEventFirmwareIfNeeded(accessoryManager)
				// No-op unless launched with --marketing-capture (see MarketingCapture / PerformanceSeedData).
				await MarketingCapture.runIfNeeded(router: router, accessoryManager: accessoryManager)
				// No-op unless launched with `-switch-stress N` (node-switch crash harness).
				await SwitchStress.runIfNeeded(accessoryManager: accessoryManager, appState: appState)
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

	/// While a node switch is clearing/swapping the SwiftData container, the tab tree AND every
	/// @Query holder above it (the event-editions query lived on ContentView itself) are replaced
	/// by this SwiftData-free placeholder, so zero @Query subscriptions exist during the swap.
	/// Stale subscriptions process store-change notifications posted by ANY SwiftData save in the
	/// process (TipKit runs its own store, saving on background queues) against the swapped-out
	/// container — the switch-nodes SIGTRAP, Datadog 324bff02-6b22-11f1. The flag is flipped
	/// inside a no-animation transaction after presented dialogs settle (see the switch flow):
	/// animated List removal goes through UICollectionView batch updates, which assert when the
	/// data churns mid-flight (the SIGABRT half of the switch crashes); non-animated replacement
	/// reloads instead.
	@ViewBuilder
	private var gatedContent: some View {
		if appState.isDatabaseResetting {
			DatabaseResettingPlaceholder()
		} else {
			ActiveContent(appState: appState, router: router) {
				tabContent
			}
		}
	}

	/// Owns every SwiftData dependency of the main UI (the event-editions @Query and the
	/// presentation environment built from it) so that unmounting it during a database reset
	/// removes ALL query subscriptions, not just the ones inside the tabs.
	private struct ActiveContent<Content: View>: View {
		@ObservedObject var appState: AppState
		@ObservedObject var router: Router
		@EnvironmentObject var accessoryManager: AccessoryManager
		@Query private var eventFirmwareEditions: [EventFirmwareEntity]
		@State private var isShowingEventFirmwareInfo: Bool = false
		private let content: Content

		init(appState: AppState, router: Router, @ViewBuilder content: () -> Content) {
			self.appState = appState
			self.router = router
			self.content = content()
		}

		private var eventPresentation: EventFirmwarePresentation? {
			EventFirmwarePresentation.resolve(
				isConnected: accessoryManager.isConnected,
				edition: accessoryManager.firmwareEdition,
				metadata: eventFirmwareEditions,
				deviceFirmwareVersion: accessoryManager.connectedVersion
			)
		}

		var body: some View {
			content
				.environment(\.eventFirmwarePresentation, eventPresentation)
				.environment(\.openEventFirmwareInfo) {
					isShowingEventFirmwareInfo = true
				}
				.sheet(isPresented: $isShowingEventFirmwareInfo) {
					if let eventPresentation {
						EventFirmwareInfoView(
							edition: eventPresentation.edition,
							info: eventPresentation.info,
							deviceFirmwareVersion: eventPresentation.deviceFirmwareVersion
						)
					}
				}
				.onChange(of: eventPresentation?.edition) { _, edition in
					if edition == nil {
						isShowingEventFirmwareInfo = false
					}
				}
		}
	}

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

// MARK: - Reset Placeholder

/// SwiftData-free stand-in shown while a node switch clears/swaps the container. Shared by
/// the WindowGroup-root gate in MeshtasticAppleApp (which unmounts the `.modelContainer`
/// modifier itself — its SwiftData↔SwiftUI bridge observes save notifications process-wide
/// and does NOT rebind when the container underneath it is swapped; a restore-time save then
/// traps in the stale bridge, the "silent" half of Datadog 324bff02) and by ContentView's
/// inner gate (defense in depth).
struct DatabaseResettingPlaceholder: View {
	var body: some View {
		VStack(spacing: 16) {
			ProgressView()
				.controlSize(.large)
			Text("Switching Radios")
				.font(.title3)
			Text("Backing up and restoring the node database…")
				.font(.callout)
				.foregroundColor(.gray)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}
