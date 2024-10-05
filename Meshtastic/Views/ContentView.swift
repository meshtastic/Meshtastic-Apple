/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

struct ContentView: View {
	@ObservedObject
	var appState: AppState

	@ObservedObject
	var router: Router

	var body: some View {
		TabView(selection: $appState.router.navigationState.selectedTab) {
			Messages(
				router: appState.router,
				unreadChannelMessages: $appState.unreadChannelMessages,
				unreadDirectMessages: $appState.unreadDirectMessages
			)
			.tabItem {
				Label("messages", systemImage: "message")
			}
			.tag(NavigationState.Tab.messages)
			.badge(appState.totalUnreadMessages)

			Connect()
				.tabItem {
					Label("bluetooth", systemImage: "antenna.radiowaves.left.and.right")
				}
				.tag(NavigationState.Tab.bluetooth)

			NodeList(
				router: appState.router
			)
			.tabItem {
				Label("nodes", systemImage: "flipphone")
			}
			.tag(NavigationState.Tab.nodes)

			MeshMap(router: appState.router)
				.tabItem {
					Label("map", systemImage: "map")
				}
				.tag(NavigationState.Tab.map)

			Settings(
				router: appState.router
			)
			.tabItem {
				Label("settings", systemImage: "gear")
					.font(.title)
			}
			.tag(NavigationState.Tab.settings)
		}
	}
}
