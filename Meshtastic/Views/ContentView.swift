/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

struct ContentView: View {
	@ObservedObject var appState: AppState

	@ObservedObject var router: Router
	@State var isShowingDeviceOnboardingFlow: Bool = false

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
}
