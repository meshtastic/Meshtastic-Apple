/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

struct ContentView: View {
	@ObservedObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State var router: Router
	@State var isShowingDeviceOnboardingFlow: Bool = false

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
			.onAppear {
				if UserDefaults.firstLaunch {
					isShowingDeviceOnboardingFlow = true
				}
			}
			.onChange(of: UserDefaults.showDeviceOnboarding) {_, newValue in
				isShowingDeviceOnboardingFlow = newValue
			}
	}

	// MARK: - Tab Content

	@ViewBuilder
	private var tabContent: some View {
		if #available(iOS 18.0, macCatalyst 18.0, *) {
			TabView(selection: $appState.router.selectedTab) {
				Tab("Messages", systemImage: "message", value: NavigationState.Tab.messages) {
					Messages(
						router: appState.router,
						unreadChannelMessages: $appState.unreadChannelMessages,
						unreadDirectMessages: $appState.unreadDirectMessages
					)
				}
				.badge(appState.totalUnreadMessages)

				Tab("Connect", systemImage: "link", value: NavigationState.Tab.connect) {
					Connect(
						router: appState.router
					)
				}

				Tab("Nodes", systemImage: "flipphone", value: NavigationState.Tab.nodes) {
					NodeList(
						router: appState.router
					)
				}

				Tab("Mesh Map", systemImage: "map", value: NavigationState.Tab.map) {
					MeshMap(router: appState.router)
				}

				Tab("Settings", systemImage: "gear", value: NavigationState.Tab.settings) {
					Settings(
						router: appState.router
					)
				}
			}
		} else {
			TabView(selection: $appState.router.selectedTab) {
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
				}
				.tag(NavigationState.Tab.settings)
			}
		}
	}
}
