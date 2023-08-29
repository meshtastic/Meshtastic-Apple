/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

struct ContentView: View {
	@StateObject var appState = AppState.shared
	var body: some View {
		TabView(selection: $appState.tabSelection) {
			Contacts()
				.tabItem {
					Label("messages", systemImage: "message")
				}
				.tag(Tab.contacts)
				.badge(42)
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
				.badge(11)
			NodeMap()
				.tabItem {
					Label("map", systemImage: "map")
				}
				.tag(Tab.map)
				.badge(4)
			Settings()
				.tabItem {
					Label("settings", systemImage: "gear")
						.font(.title)
				}
				.tag(Tab.settings)
		}
	}
}

struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		ContentView()
	}
}

enum Tab {
	case contacts
	case messages
	case map
	case ble
	case nodes
	case settings
}
