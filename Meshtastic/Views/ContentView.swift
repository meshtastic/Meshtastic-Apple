/*
 Copyright (c) Garth Vander Houwen 2021
 */

import SwiftUI

@available(iOS 17.0, *)
struct ContentView: View {

	@StateObject var appState = AppState.shared
	var body: some View {
		TabView(selection: $appState.tabSelection) {
			Messages()
				.tabItem {
					Label("messages", systemImage: "message")
				}
				.tag(Tab.contacts)
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
			if #available(iOS 17.0, macOS 14.0, *) {
				if UserDefaults.mapUseLegacy {
					NodeMap()
						.tabItem {
							Label("map", systemImage: "map")
						}
						.tag(Tab.map)
				} else {
					MeshMap()
						.tabItem {
							Label("map", systemImage: "map")
						}
						.tag(Tab.map)
				}
			} else {
				NodeMap()
					.tabItem {
						Label("map", systemImage: "map")
					}
					.tag(Tab.map)
			}
			Settings()
				.tabItem {
					Label("settings", systemImage: "gear")
						.font(.title)
				}
				.tag(Tab.settings)
		}
	}
}
//#Preview {
//	if #available(iOS 17.0, *) {
//	//	ContentView(deepLinkManager: .init())
//	} else {
//		// Fallback on earlier versions
//	}
//}

//struct ContentView_Previews: PreviewProvider {
//	static var previews: some View {
//		ContentView()
//	}
//}

enum Tab: Hashable {
	case contacts
	case messages
	case map
	case ble
	case nodes
	case settings
}
