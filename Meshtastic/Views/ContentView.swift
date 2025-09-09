/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

struct ContentView: View {
	@EnvironmentObject var appState: AppState
	@EnvironmentObject var accessoryManager: AccessoryManager
	@EnvironmentObject var router: Router

	init() {
		UITabBar.appearance().scrollEdgeAppearance = UITabBarAppearance(idiom: .unspecified)
	}

	var body: some View {
		TabView(selection: $router.navigationState.selectedTab) {
			Messages()
			.tabItem {
				Label("Messages", systemImage: "message")
			}
			.tag(NavigationState.Tab.messages)
			.badge(appState.totalUnreadMessages)

			Connect()
				.tabItem {
					Label("Connect", systemImage: "link")
				}
				.tag(NavigationState.Tab.connect)

			NodeList()
			.tabItem {
				Label("Nodes", systemImage: "flipphone")
			}
			.tag(NavigationState.Tab.nodes)

			MeshMap()
				.tabItem {
					Label("Mesh Map", systemImage: "map")
				}
				.tag(NavigationState.Tab.map)

			Settings()
			.tabItem {
				Label("Settings", systemImage: "gear")
					.font(.title)
			}
			.tag(NavigationState.Tab.settings)
		}
		.sheet(item: $appState.activeSheet) { sheet in
			switch sheet {
			case .deviceOnboarding:
				DeviceOnboarding(onboardingCompleted: {
					appState.activeSheet = nil
					UserDefaults.firstLaunch = false
					accessoryManager.startDiscovery()
				})
			case .channelSettings(let channelSettings, let addChannels):
				SaveChannelQRCode(
					channelSetLink: channelSettings,
					addChannels: addChannels,
					accessoryManager: accessoryManager
				)
			}
		}
		.onAppear {
			if UserDefaults.firstLaunch {
				appState.activeSheet = .deviceOnboarding
			}
		}
	}
}

extension View {
	func hideKeyboard() {
		UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
	}
}
