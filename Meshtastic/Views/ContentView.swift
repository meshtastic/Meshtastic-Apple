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
	///
	/// **iOS 18+ only.** Its setter writes back into the `Router` its getter reads,
	/// which the modern `Tab(value:)` API handles but iOS 17's legacy `TabView`
	/// does not: during first layout iOS 17 re-drives the selection, the write
	/// republishes, the body invalidates, and SwiftUI re-enters the attribute graph
	/// until it trips `_assertionFailure` — a launch crash seen only on iOS 17
	/// (Datadog issue bb11da86, 100% iOS 17, all at ApplicationLaunch). Same family
	/// as the lockdown-gate binding fixed above. iOS 17 binds `Router.selectedTab`
	/// directly instead and forgoes tap-to-pop.
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
			ActiveContent(appState: appState, router: router, isOnboarding: isShowingDeviceOnboardingFlow) {
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
		/// True while the first-launch device-onboarding sheet is up. The event sheet
		/// must not auto-present over it — two sheets presented from different levels
		/// of the tree fight, and the event sheet ends up covering onboarding.
		let isOnboarding: Bool
		@Query private var eventFirmwareEditions: [EventFirmwareEntity]
		@State private var isShowingEventFirmwareInfo: Bool = false
		/// The post-event upgrade sheet auto-presents once per connect. ActiveContent is
		/// remounted for every node switch (databaseResetID), so plain @State is exactly
		/// "once per connected session".
		@State private var hasAutoPresentedEventEnded: Bool = false
		private let content: Content

		init(
			appState: AppState,
			router: Router,
			isOnboarding: Bool,
			@ViewBuilder content: () -> Content
		) {
			self.appState = appState
			self.router = router
			self.isOnboarding = isOnboarding
			self.content = content()
		}

		/// Once the event's end date has passed, surface the info sheet (with its
		/// post-event update call to action) automatically on connect — parity with
		/// Android's post-event upgrade prompt; hasEnded() is false without a valid
		/// end date, so live/undated editions never nag. Held back while the
		/// onboarding sheet is up, and retried when it closes.
		private func autoPresentEndedEventIfNeeded() {
			guard !isOnboarding, !hasAutoPresentedEventEnded,
				  let presentation = eventPresentation,
				  presentation.info.hasEnded() else { return }
			hasAutoPresentedEventEnded = true
			isShowingEventFirmwareInfo = true
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
							deviceFirmwareVersion: eventPresentation.deviceFirmwareVersion,
							onUpdateFirmware: {
								// Route to the verified firmware-update flow (Settings →
								// Firmware Updates); the sheet dismissed itself first.
								router.selectedTab = .settings
								router.settingsPath = [.firmwareUpdates]
							}
						)
					}
				}
				.onChange(of: eventPresentation?.edition) { _, edition in
					guard edition != nil else {
						isShowingEventFirmwareInfo = false
						return
					}
					autoPresentEndedEventIfNeeded()
				}
				.onChange(of: isOnboarding) { _, onboarding in
					// Onboarding just finished — show the sheet we held back. Without this
					// a first launch that connects during setup never gets the prompt.
					if !onboarding { autoPresentEndedEventIfNeeded() }
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
					.trackScreen(NavigationState.Tab.messages.screenName)
				}
				.badge(appState.totalUnreadMessages)

				Tab("Nodes", image: "custom.mesh.radio", value: NavigationState.Tab.nodes) {
					NodeList()
						.trackScreen(NavigationState.Tab.nodes.screenName)
				}

				Tab("Map", systemImage: "map", value: NavigationState.Tab.map) {
					MeshMapMK(router: appState.router)
						.trackScreen(NavigationState.Tab.map.screenName)
				}

				Tab("Settings", systemImage: "gear", value: NavigationState.Tab.settings) {
					Settings()
						.trackScreen(NavigationState.Tab.settings.screenName)
				}

				Tab("Connect", systemImage: "link", value: NavigationState.Tab.connect) {
					Connect(
						router: appState.router
					)
					.trackScreen(NavigationState.Tab.connect.screenName)
				}
			}
		} else {
			// iOS 17 gets the legacy TabView, which differs from iOS 18's `Tab` in two
			// ways that matter here. Its selection is bound straight to the stored
			// @Published value rather than the side-effecting `tabSelection` (so no
			// tap-to-pop on 17), and each tab's content is built lazily instead of all
			// five roots — and their @Query subscriptions — being constructed during
			// first layout. `Tab`'s @ViewBuilder closure gives iOS 18+ that laziness
			// for free. Datadog issue bb11da86 is an attribute-graph trap at first
			// layout seen only on iOS 17; shrinking what that pass has to build is the
			// mitigation, and it also cuts the tab-switch cost on 17.
			TabView(selection: $router.selectedTab) {
				ForEach(LegacyTab.allCases) { tab in
					LegacyTabContent(tab: tab, isActive: router.selectedTab == tab.value) {
						legacyContent(for: tab)
					}
					.tabItem { tab.label }
					.tag(tab.value)
					.badge(tab == .messages ? appState.totalUnreadMessages : 0)
				}
			}
		}
	}

	/// Tabs for the iOS 17 legacy `TabView`, mirroring the iOS 18 `Tab` list.
	private enum LegacyTab: String, CaseIterable, Identifiable {
		case messages, nodes, map, settings, connect

		var id: String { rawValue }

		var value: NavigationState.Tab {
			switch self {
			case .messages: return .messages
			case .nodes: return .nodes
			case .map: return .map
			case .settings: return .settings
			case .connect: return .connect
			}
		}

		@ViewBuilder
		var label: some View {
			switch self {
			case .messages: Label("Messages", systemImage: "message")
			case .nodes: Label("Nodes", image: "custom.mesh.radio")
			case .map: Label("Map", systemImage: "map")
			case .settings: Label("Settings", systemImage: "gear")
			case .connect: Label("Connect", systemImage: "link")
			}
		}
	}

	@ViewBuilder
	private func legacyContent(for tab: LegacyTab) -> some View {
		switch tab {
		case .messages:
			Messages(
				router: appState.router,
				unreadChannelMessages: $appState.unreadChannelMessages,
				unreadDirectMessages: $appState.unreadDirectMessages
			)
			.trackScreen(tab.value.screenName)
		case .nodes: NodeList().trackScreen(tab.value.screenName)
		case .map: MeshMapMK(router: appState.router).trackScreen(tab.value.screenName)
		case .settings: Settings().trackScreen(tab.value.screenName)
		case .connect: Connect(router: appState.router).trackScreen(tab.value.screenName)
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

/// Defers a legacy-`TabView` tab's content until the tab is first selected, then
/// keeps it alive so its state survives further tab switches.
///
/// The iOS 17 `TabView { A; B; C }` form constructs every tab's root immediately,
/// which on this app means five view trees and their `@Query` subscriptions all
/// come up during first layout. iOS 18's `Tab(value:) { }` takes a closure and is
/// lazy already, so this exists only for the iOS 17 path.
private struct LegacyTabContent<Content: View>: View {
	let tab: AnyHashable
	let isActive: Bool
	@ViewBuilder let content: () -> Content
	/// Latched on first activation — never reset, so a tab keeps its navigation
	/// state once visited, matching the eager behaviour from the second visit on.
	@State private var hasActivated = false

	var body: some View {
		Group {
			if hasActivated {
				content()
			} else {
				Color(.systemBackground)
			}
		}
		.onAppear { if isActive { hasActivated = true } }
		.onChange(of: isActive) { _, active in
			if active { hasActivated = true }
		}
	}
}
