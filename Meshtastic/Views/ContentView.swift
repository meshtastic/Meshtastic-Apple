/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

@available(iOS 17.0, *)
struct ContentView: View {

	@StateObject var appState = AppState.shared

	var meshMap: some View {
		SwiftUI.Group {
			if #available(iOS 17.0, macOS 14.0, *), !UserDefaults.mapUseLegacy {
				MeshMap()
			} else {
				NodeMap()
			}
		}
	}

	var body: some View {
		TabView(selection: $appState.tabSelection) {
			Messages()
				.tabItem {
					Label("messages", systemImage: "message")
				}
				.tag(Tab.messages)
				.badge(appState.unreadDirectMessages + appState.unreadChannelMessages)
			Connect()
				.tabItem {
					Label("bluetooth", systemImage: "antenna.radiowaves.left.and.right")
				}
				.tag(Tab.ble)
			NodeList()
				.tabItem {
					Label("nodes", systemImage: "flipphone")
				}
				.tag(Tab.nodes)
			meshMap
				.tabItem {
					Label("map", systemImage: "map")
				}
				.tag(Tab.map)
			Settings()
				.tabItem {
					Label("settings", systemImage: "gear")
						.font(.title)
				}
				.tag(Tab.settings)
		}
	}
}

enum Tab: Hashable {
	case messages
	case map
	case ble
	case nodes
	case settings
}
