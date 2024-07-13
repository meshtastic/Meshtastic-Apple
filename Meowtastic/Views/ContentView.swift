import SwiftUI

enum Tab: Hashable {
	case contacts
	case messages
	case map
	case ble
	case nodes
	case settings
}

struct ContentView: View {
	@StateObject
	private var appState = AppState.shared

	@EnvironmentObject
	private var bleManager: BLEManager

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true),
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	private var nodeCount: Int {
		if bleManager.isNodeConnected {
			nodes.count
		}
		else {
			0
		}
	}

	var body: some View {
		if !bleManager.isNodeConnected {
			Connect()
		}
		else {
			TabView(selection: $appState.tabSelection) {
				Messages()
					.tabItem {
						Label("messages", systemImage: "message")
					}
					.tag(Tab.contacts)
					.badge(appState.unreadDirectMessages + appState.unreadChannelMessages)
					.badgeProminence(.standard)

				NodeList()
					.tabItem {
						Label("nodes", systemImage: "flipphone")
					}
					.tag(Tab.nodes)
					.badge(nodeCount)
					.badgeProminence(.decreased)

				MeshMap()
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
}
