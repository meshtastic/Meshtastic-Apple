import SwiftUI

struct Content: View {
	@EnvironmentObject
	private var bleManager: BLEManager
	@StateObject
	private var appState = AppState.shared
	@State
	private var connectPresented = false
	@State
	private var connectWasDismissed = false

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
		TabView(selection: $appState.tabSelection) {
			Messages()
				.tabItem {
					Label("Messages", systemImage: "message")
				}
				.tag(TabTag.messages)
				.badge(appState.totalUnreadMessages)
				.badgeProminence(.standard)

			NodeList()
				.tabItem {
					Label("Nodes", systemImage: "flipphone")
				}
				.tag(TabTag.nodes)
				.badge(nodeOnlineCount)
				.badgeProminence(.decreased)

			MeshMap()
				.tabItem {
					Label("Mesh", systemImage: "map")
				}
				.tag(TabTag.map)

			Options()
				.tabItem {
					Label("Options", systemImage: "gearshape")
				}
				.tag(TabTag.settings)
		}
		.onChange(of: bleManager.isSubscribed, initial: true) {
			if bleManager.isSubscribed {
				connectWasDismissed = false
				connectPresented = false
			}
			else if !connectWasDismissed {
				connectPresented = true
			}
		}
		.onChange(of: bleManager.lastConnectionError, initial: true) {
			if !bleManager.lastConnectionError.isEmpty, !connectWasDismissed {
				connectPresented = true
			}
		}
		.sheet(isPresented: $connectPresented) {
			connectPresented = false
			connectWasDismissed = true
		} content: {
			Connect(isInSheet: true)
				.presentationDetents([.large])
				.presentationDragIndicator(.visible)
		}
	}
}
