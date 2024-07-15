import SwiftUI

enum Tab: Hashable {
	case messages
	case nodes
	case map
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
						Image(systemName: "message")
					}
					.tag(Tab.messages)
					.badge(appState.unreadDirectMessages + appState.unreadChannelMessages)
					.badgeProminence(.standard)

				NodeList()
					.tabItem {
						Image(systemName: "flipphone")
					}
					.tag(Tab.nodes)
					.badge(nodeCount)
					.badgeProminence(.decreased)

				MeshMap()
					.tabItem {
						Image(systemName: "map")
					}
					.tag(Tab.map)

				Settings()
					.tabItem {
						Image(systemName: "gearshape")
					}
					.tag(Tab.settings)
			}
		}
	}
}
