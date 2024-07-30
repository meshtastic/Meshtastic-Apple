import SwiftUI

struct Content: View {
	@EnvironmentObject
	private var bleManager: BLEManager
	@StateObject
	private var appState = AppState.shared

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "favorite", ascending: false),
			NSSortDescriptor(key: "lastHeard", ascending: false),
			NSSortDescriptor(key: "user.longName", ascending: true)
		],
		animation: .default
	)
	private var nodes: FetchedResults<NodeInfoEntity>

	private var nodeOnlineCount: Int {
		if bleManager.isNodeConnected {
			nodes.filter { node in
				node.isOnline
			}.count
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
					.badge(appState.totalUnreadMessages)
					.badgeProminence(.standard)

				NodeList()
					.tabItem {
						Image(systemName: "flipphone")
					}
					.tag(Tab.nodes)
					.badge(nodeOnlineCount)
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
