/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

struct ContentView: View {
	@ObservedObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var lockdown: LockdownCoordinator
	@State var router: Router
	@State var isShowingDeviceOnboardingFlow: Bool = false

	/// True when the connected device's lockdown state requires the user to act
	/// (provision a passphrase, unlock, or wait out a backoff). The sheet is
	/// non-dismissable; it only closes when the coordinator transitions to a
	/// non-blocking state (.none, .unlocked, .lockNowAcknowledged).
	private var isLockdownGateActive: Bool {
		switch lockdown.state {
		case .needsProvision, .locked, .unlockFailed, .unlockBackoff:
			return true
		case .none, .unlocked, .lockNowAcknowledged:
			return false
		}
	}

	init(appState: AppState, router: Router) {
		self.appState = appState
		self.router = router
		UITabBar.appearance().scrollEdgeAppearance = UITabBarAppearance(idiom: .unspecified)
	}

	var body: some View {
		TabView(selection: $appState.router.navigationState.selectedTab) {
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

			Connect(
					router: appState.router
				)
				.tabItem {
					Label("Connect", systemImage: "link")
				}
				.tag(NavigationState.Tab.connect)

			NodeList(
				router: appState.router
			)
			.tabItem {
				Label("Nodes", systemImage: "flipphone")
			}
			.tag(NavigationState.Tab.nodes)

			MeshMap(router: appState.router)
				.tabItem {
					Label("Mesh Map", systemImage: "map")
				}
				.tag(NavigationState.Tab.map)

			Settings(
				router: appState.router
			)
			.tabItem {
				Label("Settings", systemImage: "gear")
					.font(.title)
			}
			.tag(NavigationState.Tab.settings)
		}.sheet(
			isPresented: $isShowingDeviceOnboardingFlow,
			onDismiss: {
				UserDefaults.firstLaunch = false
				accessoryManager.startDiscovery()
			}, content: {
				DeviceOnboarding()
			}
		)
		.fullScreenCover(isPresented: Binding(
			get: { isLockdownGateActive },
			set: { _ in /* non-dismissable; coordinator state controls visibility */ }
		)) {
			LockdownSheet()
		}
		.onAppear {
			if UserDefaults.firstLaunch {
				isShowingDeviceOnboardingFlow = true
			}
		}
		.onChange(of: UserDefaults.showDeviceOnboarding) {_, newValue in
			isShowingDeviceOnboardingFlow = newValue
		}
	}
}
