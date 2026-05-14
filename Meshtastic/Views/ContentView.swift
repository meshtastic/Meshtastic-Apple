/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

struct ContentView: View {
	@ObservedObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@ObservedObject var router: Router
	@State var isShowingDeviceOnboardingFlow: Bool = false
	@AppStorage("isMeshMapWindowOpen") private var isMeshMapWindowOpen = false

	private var isDetachedMapActive: Bool {
		isMeshMapWindowOpen
	}

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
				router.mapWindowOpen = isMeshMapWindowOpen
				if isMeshMapWindowOpen && router.selectedTab == .map {
					router.selectedTab = .nodes
				}
			}
			.onChange(of: UserDefaults.showDeviceOnboarding) {_, newValue in
				isShowingDeviceOnboardingFlow = newValue
			}
			.onChange(of: isMeshMapWindowOpen) { _, isOpen in
				router.mapWindowOpen = isOpen
				if isOpen && router.selectedTab == .map {
					router.selectedTab = .nodes
				}
			}
	}

	// MARK: - Tab Content

	@ViewBuilder
	private var tabContent: some View {
		if #available(iOS 18.0, macCatalyst 18.0, *) {
			TabView(selection: $router.selectedTab) {
				Tab("Messages", systemImage: "message", value: NavigationState.Tab.messages) {
					Messages(
						router: router,
						unreadChannelMessages: $appState.unreadChannelMessages,
						unreadDirectMessages: $appState.unreadDirectMessages
					)
				}
				.badge(appState.totalUnreadMessages)

				Tab("Connect", systemImage: "link", value: NavigationState.Tab.connect) {
					Connect(
						router: router
					)
				}

				Tab("Nodes", systemImage: "flipphone", value: NavigationState.Tab.nodes) {
					NodeList()
				}

				if !isDetachedMapActive {
					Tab("Mesh Map", systemImage: "map", value: NavigationState.Tab.map) {
						MeshMap(router: router)
					}
				}

				Tab("Settings", systemImage: "gear", value: NavigationState.Tab.settings) {
					Settings()
				}
			}
			.id(isDetachedMapActive)
		} else {
			TabView(selection: $router.selectedTab) {
				Messages(
					router: router,
					unreadChannelMessages: $appState.unreadChannelMessages,
					unreadDirectMessages: $appState.unreadDirectMessages
				)
				.tabItem {
					Label("Messages", systemImage: "message")
				}
				.tag(NavigationState.Tab.messages)
				.badge(appState.totalUnreadMessages)

				Connect(
					router: router
				)
				.tabItem {
					Label("Connect", systemImage: "link")
				}
				.tag(NavigationState.Tab.connect)

				NodeList()
				.tabItem {
					Label("Nodes", systemImage: "flipphone")
				}
				.tag(NavigationState.Tab.nodes)

				if !isDetachedMapActive {
					MeshMap(router: router)
					.tabItem {
						Label("Mesh Map", systemImage: "map")
					}
					.tag(NavigationState.Tab.map)
				}

				Settings()
				.tabItem {
					Label("Settings", systemImage: "gear")
				}
				.tag(NavigationState.Tab.settings)
			}
			.id(isDetachedMapActive)
		}
	}
}
