/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

struct ContentView: View {
	@ObservedObject
	var appState: AppState

	@ObservedObject
	var router: Router

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

			Connect()
				.tabItem {
					Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
				}
				.tag(NavigationState.Tab.bluetooth)

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
		}
	}
}
